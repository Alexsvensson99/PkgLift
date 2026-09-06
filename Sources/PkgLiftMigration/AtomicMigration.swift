//
//  AtomicMigration.swift
//  PkgLiftMigration
//

import Darwin
import Foundation

/// Transaction-like migration with durable, fail-closed recovery state.
public struct AtomicMigration: Sendable {
    public struct RollbackFailure: Sendable, Equatable {
        public let path: String
        public let message: String

        public init(path: String, message: String) {
            self.path = path
            self.message = message
        }
    }

    public enum MigrationError: Error, LocalizedError {
        case actionFailed(underlyingError: Error)
        case rollbackFailed(underlyingError: Error, rollbackErrors: [RollbackFailure])
        case incompleteMigration(markerPath: String, backupPath: String)
        case unsafeRecoveryState(String)
        case invalidMigrationInput(String)
        case recoveryStateOperationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .actionFailed(let error):
                return "Migration failed and was rolled back. Underlying error: \(error.localizedDescription)"
            case .rollbackFailed(let error, let rollbackErrors):
                let detail = rollbackErrors
                    .map { "\($0.path): \($0.message)" }
                    .joined(separator: "; ")
                return "Migration failed and rollback was incomplete. The recovery marker and backup were preserved. Underlying error: \(error.localizedDescription). Rollback errors: \(detail)"
            case .incompleteMigration(let markerPath, let backupPath):
                return "An incomplete migration is recorded at '\(markerPath)'. The recovery backup at '\(backupPath)' was preserved; inspect and resolve it before applying another migration."
            case .unsafeRecoveryState(let detail):
                return "Migration refused because recovery state is unsafe or incomplete: \(detail)"
            case .invalidMigrationInput(let detail):
                return "Migration refused because its atomic input is invalid: \(detail)"
            case .recoveryStateOperationFailed(let detail):
                return "Migration recovery state could not be updated safely: \(detail)"
            }
        }
    }

    private struct ActiveMarker: Codable, Equatable {
        let schemaVersion: Int
        let files: [String]
        let backupDirectory: String
    }

    private struct CompletedReceipt: Codable, Equatable {
        enum Outcome: String, Codable {
            case applied
            case rolledBack
        }

        let schemaVersion: Int
        let files: [String]
        let backupDirectory: String
        let outcome: Outcome
    }

    private static let schemaVersion = 1
    private static let markerName = "migration-in-progress"
    private static let receiptName = ".pkglift-completed.json"

    public init() {}

    /// Refuses an active marker or any backup that is not proven terminal.
    public static func checkForIncompleteMigration(backupDir: URL) throws {
        let locations = try recoveryLocations(for: backupDir, createParent: false)
        if try pathKind(at: locations.marker) != nil {
            throw MigrationError.incompleteMigration(
                markerPath: locations.marker.path,
                backupPath: locations.backup.path
            )
        }

        guard let backupKind = try pathKind(at: locations.backup) else { return }
        guard backupKind == .directory else {
            throw MigrationError.unsafeRecoveryState(
                "'\(locations.backup.path)' is not a regular directory"
            )
        }
        _ = try loadCompletedReceipt(at: locations.receipt, expectedBackup: locations.canonicalBackup)
    }

    /// Copies every required original into a recovery backup, performs the
    /// action, and restores every original if mutation does not complete.
    public func perform(
        files: [URL],
        backupDir: URL,
        checkCancellation: () throws -> Void = {},
        action: () throws -> Void
    ) throws {
        try checkCancellation()
        let originals = try Self.validateOriginals(files)
        let proposedLocations = try Self.recoveryLocations(for: backupDir, createParent: false)
        try Self.validateRecoverySeparation(originals: originals, locations: proposedLocations)
        let locations = try Self.recoveryLocations(for: backupDir, createParent: true)
        let marker = ActiveMarker(
            schemaVersion: Self.schemaVersion,
            files: originals.map(\.path).sorted(),
            backupDirectory: locations.canonicalBackup.path
        )
        let markerData = try Self.encode(marker)

        try checkCancellation()
        try Self.createExclusiveFile(at: locations.marker, data: markerData)
        var createdBackup = false
        var backedUpFiles: [(original: URL, backup: URL)] = []

        do {
            try checkCancellation()
            if let existingBackupKind = try Self.pathKind(at: locations.backup) {
                guard existingBackupKind == .directory else {
                    throw MigrationError.unsafeRecoveryState(
                        "occupied backup '\(locations.backup.path)' is not a non-symlink directory"
                    )
                }
                let receipt = try Self.loadCompletedReceipt(
                    at: locations.receipt,
                    expectedBackup: locations.canonicalBackup
                )
                guard receipt.files == marker.files else {
                    throw MigrationError.unsafeRecoveryState(
                        "the completed receipt does not match the files in this migration"
                    )
                }
                try FileManager.default.removeItem(at: locations.backup)
            }

            try Self.createExclusiveDirectory(at: locations.backup)
            createdBackup = true
            try Self.synchronizeDirectory(at: locations.backup.deletingLastPathComponent())
            for original in originals {
                try checkCancellation()
                let backup = locations.backup.appendingPathComponent(original.lastPathComponent)
                try FileManager.default.copyItem(at: original, to: backup)
                backedUpFiles.append((original, backup))
                try checkCancellation()
            }
            try Self.synchronizeTree(at: locations.backup)
            try checkCancellation()
        } catch {
            let cleanupErrors = Self.cleanupPreparation(
                marker: locations.marker,
                expectedMarkerData: markerData,
                backup: createdBackup ? locations.backup : nil
            )
            if cleanupErrors.isEmpty {
                throw error
            }
            throw MigrationError.rollbackFailed(
                underlyingError: error,
                rollbackErrors: cleanupErrors
            )
        }

        do {
            try checkCancellation()
            try action()
            try checkCancellation()
            try Self.synchronizeOriginals(originals)
            try checkCancellation()
            try Self.finish(
                outcome: .applied,
                marker: locations.marker,
                expectedMarkerData: markerData,
                receipt: locations.receipt,
                files: marker.files,
                backup: locations.canonicalBackup
            )
        } catch {
            let rollbackErrors = Self.restoreAll(backedUpFiles)
            guard rollbackErrors.isEmpty else {
                throw MigrationError.rollbackFailed(
                    underlyingError: error,
                    rollbackErrors: rollbackErrors
                )
            }

            do {
                try Self.finish(
                    outcome: .rolledBack,
                    marker: locations.marker,
                    expectedMarkerData: markerData,
                    receipt: locations.receipt,
                    files: marker.files,
                    backup: locations.canonicalBackup
                )
            } catch let finalizationError {
                throw MigrationError.rollbackFailed(
                    underlyingError: error,
                    rollbackErrors: [
                        RollbackFailure(
                            path: locations.marker.path,
                            message: finalizationError.localizedDescription
                        )
                    ]
                )
            }
            throw MigrationError.actionFailed(underlyingError: error)
        }
    }

    private enum PathKind: Equatable {
        case regularFile
        case directory
        case symbolicLink
        case other
    }

    private static func recoveryLocations(for backupDir: URL, createParent: Bool) throws -> (
        backup: URL,
        canonicalBackup: URL,
        marker: URL,
        receipt: URL
    ) {
        let backup = backupDir.standardizedFileURL
        let parent = backup.deletingLastPathComponent()
        if try pathKind(at: parent) == nil, createParent {
            try createExclusiveDirectory(at: parent)
            try synchronizeDirectory(at: parent.deletingLastPathComponent())
        }
        let parentKind = try pathKind(at: parent)
        guard parentKind == nil || parentKind == .directory else {
            throw MigrationError.unsafeRecoveryState(
                "recovery parent '\(parent.path)' must be a non-symlink directory"
            )
        }
        guard !createParent || parentKind == .directory else {
            throw MigrationError.recoveryStateOperationFailed(
                "recovery parent '\(parent.path)' could not be created"
            )
        }
        let canonicalBackup = backup.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalBackup.deletingLastPathComponent().path == parent.resolvingSymlinksInPath().path else {
            throw MigrationError.unsafeRecoveryState("the backup directory escapes its recovery parent")
        }
        return (
            backup,
            canonicalBackup,
            parent.appendingPathComponent(markerName),
            backup.appendingPathComponent(receiptName)
        )
    }

    private static func validateOriginals(_ files: [URL]) throws -> [URL] {
        guard !files.isEmpty else {
            throw MigrationError.invalidMigrationInput("at least one original file is required")
        }
        let standardized = files.map(\.standardizedFileURL)
        let foldedNames = standardized.map { $0.lastPathComponent.lowercased() }
        guard Set(foldedNames).count == standardized.count else {
            throw MigrationError.invalidMigrationInput("backup file names must be unique")
        }
        guard !foldedNames.contains(receiptName.lowercased()) else {
            throw MigrationError.invalidMigrationInput(
                "an original file name conflicts with the reserved completed receipt"
            )
        }

        var canonical: [URL] = []
        for file in standardized {
            guard let kind = try pathKind(at: file) else {
                throw MigrationError.invalidMigrationInput("required original '\(file.path)' does not exist")
            }
            guard kind == .regularFile || kind == .directory else {
                throw MigrationError.invalidMigrationInput(
                    "required original '\(file.path)' must be a non-symlink file or directory"
                )
            }
            canonical.append(file.resolvingSymlinksInPath().standardizedFileURL)
        }
        guard Set(canonical.map(\.path)).count == canonical.count else {
            throw MigrationError.invalidMigrationInput("original paths must be unique")
        }
        return canonical
    }

    private static func validateRecoverySeparation(
        originals: [URL],
        locations: (backup: URL, canonicalBackup: URL, marker: URL, receipt: URL)
    ) throws {
        let statePaths = [locations.canonicalBackup.path, locations.marker.standardizedFileURL.path]
        for original in originals {
            for statePath in statePaths where pathsOverlap(original.path, statePath) {
                throw MigrationError.invalidMigrationInput(
                    "original '\(original.path)' overlaps migration recovery state at '\(statePath)'"
                )
            }
        }
    }

    private static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
    }

    private static func finish(
        outcome: CompletedReceipt.Outcome,
        marker: URL,
        expectedMarkerData: Data,
        receipt: URL,
        files: [String],
        backup: URL
    ) throws {
        let completed = CompletedReceipt(
            schemaVersion: schemaVersion,
            files: files,
            backupDirectory: backup.path,
            outcome: outcome
        )
        try writeAtomicallyAndSynchronize(try encode(completed), to: receipt)
        try removeOwnedMarker(at: marker, expectedData: expectedMarkerData)
    }

    private static func restoreAll(
        _ files: [(original: URL, backup: URL)]
    ) -> [RollbackFailure] {
        var failures: [RollbackFailure] = []
        for pair in files {
            let staging = pair.original.deletingLastPathComponent()
                .appendingPathComponent(".pkglift-restore-\(UUID().uuidString)")
            do {
                try FileManager.default.copyItem(at: pair.backup, to: staging)
                try synchronizeTree(at: staging)
                if try pathKind(at: pair.original) != nil {
                    try FileManager.default.removeItem(at: pair.original)
                }
                try FileManager.default.moveItem(at: staging, to: pair.original)
                try synchronizeTree(at: pair.original)
                try synchronizeDirectory(at: pair.original.deletingLastPathComponent())
            } catch {
                try? FileManager.default.removeItem(at: staging)
                failures.append(RollbackFailure(path: pair.original.path, message: error.localizedDescription))
            }
        }
        return failures
    }

    private static func cleanupPreparation(
        marker: URL,
        expectedMarkerData: Data,
        backup: URL?
    ) -> [RollbackFailure] {
        var failures: [RollbackFailure] = []
        if let backup {
            do {
                try FileManager.default.removeItem(at: backup)
            } catch {
                failures.append(RollbackFailure(path: backup.path, message: error.localizedDescription))
            }
        }
        if failures.isEmpty {
            do {
                try removeOwnedMarker(at: marker, expectedData: expectedMarkerData)
            } catch {
                failures.append(RollbackFailure(path: marker.path, message: error.localizedDescription))
            }
        }
        return failures
    }

    private static func loadCompletedReceipt(
        at receipt: URL,
        expectedBackup: URL
    ) throws -> CompletedReceipt {
        guard try pathKind(at: receipt) == .regularFile else {
            throw MigrationError.unsafeRecoveryState(
                "occupied backup '\(expectedBackup.path)' has no safe completed receipt"
            )
        }
        do {
            let value = try JSONDecoder().decode(
                CompletedReceipt.self,
                from: readBoundedRegularFile(at: receipt)
            )
            guard value.schemaVersion == schemaVersion,
                  value.backupDirectory == expectedBackup.path,
                  !value.files.isEmpty,
                  Set(value.files).count == value.files.count else {
                throw MigrationError.unsafeRecoveryState("the completed backup receipt does not match its location")
            }
            return value
        } catch let error as MigrationError {
            throw error
        } catch {
            throw MigrationError.unsafeRecoveryState(
                "completed backup receipt is unreadable or malformed: \(error.localizedDescription)"
            )
        }
    }

    private static func createExclusiveDirectory(at url: URL) throws {
        guard Darwin.mkdir(url.path, mode_t(0o700)) == 0 else {
            throw MigrationError.recoveryStateOperationFailed(posixFailure("create '\(url.path)'"))
        }
    }

    private static func createExclusiveFile(at url: URL, data: Data) throws {
        let descriptor = Darwin.open(
            url.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            if errno == EEXIST || errno == ELOOP {
                throw MigrationError.incompleteMigration(
                    markerPath: url.path,
                    backupPath: url.deletingLastPathComponent().appendingPathComponent("backup").path
                )
            }
            throw MigrationError.recoveryStateOperationFailed(posixFailure("create '\(url.path)'"))
        }
        defer { _ = Darwin.close(descriptor) }
        do {
            try writeAll(data, to: descriptor, path: url.path)
            guard Darwin.fsync(descriptor) == 0 else {
                throw MigrationError.recoveryStateOperationFailed(posixFailure("synchronize '\(url.path)'"))
            }
            try synchronizeDirectory(at: url.deletingLastPathComponent())
        } catch {
            // A failed write/flush during setup must not leave a misleading
            // partial marker when it can be removed safely. Never unlink a
            // path that another actor has replaced since our exclusive open.
            var owned = stat()
            var current = stat()
            if Darwin.fstat(descriptor, &owned) == 0,
               Darwin.lstat(url.path, &current) == 0,
               owned.st_dev == current.st_dev, owned.st_ino == current.st_ino,
               Darwin.unlink(url.path) == 0 {
                try? synchronizeDirectory(at: url.deletingLastPathComponent())
            }
            throw error
        }
    }

    private static func writeAtomicallyAndSynchronize(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp")
        if try pathKind(at: temporary) != nil {
            throw MigrationError.unsafeRecoveryState("temporary receipt '\(temporary.path)' already exists")
        }
        try createExclusiveFile(at: temporary, data: data)
        guard Darwin.rename(temporary.path, url.path) == 0 else {
            let detail = posixFailure("commit receipt '\(url.path)'")
            try? FileManager.default.removeItem(at: temporary)
            throw MigrationError.recoveryStateOperationFailed(detail)
        }
        try synchronizeDirectory(at: url.deletingLastPathComponent())
    }

    private static func removeOwnedMarker(at url: URL, expectedData: Data) throws {
        guard try pathKind(at: url) == .regularFile,
              try readBoundedRegularFile(at: url) == expectedData else {
            throw MigrationError.unsafeRecoveryState(
                "active marker ownership could not be verified at '\(url.path)'"
            )
        }
        guard Darwin.unlink(url.path) == 0 else {
            throw MigrationError.recoveryStateOperationFailed(posixFailure("remove '\(url.path)'"))
        }
        // Once the unlink succeeds the transaction is committed. A directory
        // fsync failure may conservatively leave the marker after a crash, but
        // must not trigger a rollback with no marker left to preserve.
        try? synchronizeDirectory(at: url.deletingLastPathComponent())
    }

    private static func synchronizeTree(at root: URL) throws {
        guard let rootKind = try pathKind(at: root) else {
            throw MigrationError.recoveryStateOperationFailed("cannot synchronize missing path '\(root.path)'")
        }
        if rootKind == .regularFile {
            try synchronizeFile(at: root)
            return
        }
        guard rootKind == .directory else {
            throw MigrationError.unsafeRecoveryState("recovery tree contains an unsupported file type at '\(root.path)'")
        }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        let children = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: []
        )
        for child in children {
            let values = try child.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                throw MigrationError.unsafeRecoveryState("recovery tree contains a symbolic link at '\(child.path)'")
            }
            if values.isDirectory == true {
                try synchronizeTree(at: child)
            } else if values.isRegularFile == true {
                try synchronizeFile(at: child)
            } else {
                throw MigrationError.unsafeRecoveryState("recovery tree contains an unsupported file type at '\(child.path)'")
            }
        }
        try synchronizeDirectory(at: root)
    }

    private static func synchronizeOriginals(_ originals: [URL]) throws {
        var synchronizedParents: Set<String> = []
        for original in originals {
            try synchronizeTree(at: original)
            let parent = original.deletingLastPathComponent()
            if synchronizedParents.insert(parent.path).inserted {
                try synchronizeDirectory(at: parent)
            }
        }
    }

    private static func synchronizeFile(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw MigrationError.recoveryStateOperationFailed(posixFailure("open '\(url.path)'"))
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw MigrationError.recoveryStateOperationFailed(posixFailure("synchronize '\(url.path)'"))
        }
    }

    private static func synchronizeDirectory(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw MigrationError.recoveryStateOperationFailed(posixFailure("open directory '\(url.path)'"))
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw MigrationError.recoveryStateOperationFailed(posixFailure("synchronize directory '\(url.path)'"))
        }
    }

    private static func pathKind(at url: URL) throws -> PathKind? {
        var metadata = stat()
        guard Darwin.lstat(url.path, &metadata) == 0 else {
            if errno == ENOENT { return nil }
            throw MigrationError.recoveryStateOperationFailed(posixFailure("inspect '\(url.path)'"))
        }
        switch metadata.st_mode & mode_t(S_IFMT) {
        case mode_t(S_IFREG): return .regularFile
        case mode_t(S_IFDIR): return .directory
        case mode_t(S_IFLNK): return .symbolicLink
        default: return .other
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func writeAll(_ data: Data, to descriptor: Int32, path: String) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: written), bytes.count - written)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else {
                    throw MigrationError.recoveryStateOperationFailed(posixFailure("write '\(path)'"))
                }
                written += count
            }
        }
    }

    private static func readBoundedRegularFile(at url: URL) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw MigrationError.recoveryStateOperationFailed(posixFailure("open '\(url.path)'"))
        }
        defer { _ = Darwin.close(descriptor) }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_size >= 0,
              metadata.st_size <= 64 * 1024 else {
            throw MigrationError.unsafeRecoveryState(
                "recovery metadata '\(url.path)' is not a bounded regular file"
            )
        }

        var data = Data(count: Int(metadata.st_size))
        try data.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.read(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else {
                    throw MigrationError.recoveryStateOperationFailed(posixFailure("read '\(url.path)'"))
                }
                offset += count
            }
        }
        return data
    }

    private static func posixFailure(_ operation: String) -> String {
        "Failed to \(operation): \(String(cString: strerror(errno)))"
    }
}
