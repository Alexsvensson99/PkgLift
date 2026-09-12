import CryptoKit
import Darwin
import Foundation

/// No descriptors or private path strings cross the inspection result boundary.
final class InspectionDescriptor {
    let rawValue: Int32
    init(_ rawValue: Int32) { self.rawValue = rawValue }
    deinit { _ = close(rawValue) }
}

struct InspectionFileStamp: Equatable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
    let size: off_t
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    init(_ value: stat) {
        device = value.st_dev
        inode = value.st_ino
        mode = value.st_mode
        size = value.st_size
        modifiedSeconds = value.st_mtimespec.tv_sec
        modifiedNanoseconds = value.st_mtimespec.tv_nsec
        changedSeconds = value.st_ctimespec.tv_sec
        changedNanoseconds = value.st_ctimespec.tv_nsec
    }

    var isDirectory: Bool { mode & mode_t(S_IFMT) == mode_t(S_IFDIR) }
    var isRegular: Bool { mode & mode_t(S_IFMT) == mode_t(S_IFREG) }
    var isSymlink: Bool { mode & mode_t(S_IFMT) == mode_t(S_IFLNK) }

    func sameObject(as other: Self) -> Bool {
        device == other.device && inode == other.inode
            && (mode & mode_t(S_IFMT)) == (other.mode & mode_t(S_IFMT))
    }

    static func descriptor(_ descriptor: InspectionDescriptor) throws -> Self {
        var value = stat()
        guard fstat(descriptor.rawValue, &value) == 0 else { throw inspectionSystemFailure() }
        return Self(value)
    }

    static func child(_ name: String, of directory: InspectionDescriptor) throws -> Self {
        var value = stat()
        guard fstatat(directory.rawValue, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw inspectionSystemFailure()
        }
        return Self(value)
    }

    static func child(_ nameBytes: [UInt8], of directory: InspectionDescriptor) throws -> Self {
        guard !nameBytes.isEmpty, !nameBytes.contains(0) else {
            throw LocalSourceInspectionFailure(.invalidSourcePath)
        }
        var terminatedName = nameBytes.map { Int8(bitPattern: $0) }
        terminatedName.append(0)
        var value = stat()
        let result = terminatedName.withUnsafeBufferPointer { name in
            fstatat(directory.rawValue, name.baseAddress, &value, AT_SYMLINK_NOFOLLOW)
        }
        guard result == 0 else { throw inspectionSystemFailure() }
        return Self(value)
    }
}

struct InspectionInputPath {
    let isAbsolute: Bool
    let components: [String]

    init(_ input: String) throws {
        guard !input.isEmpty,
              !input.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw LocalSourceInspectionFailure(.invalidInputPath)
        }
        isAbsolute = input.hasPrefix("/")
        let pieces = input.split(separator: "/").map(String.init)
        guard !pieces.contains("..") else { throw LocalSourceInspectionFailure(.invalidInputPath) }
        components = pieces.filter { $0 != "." }
    }
}

private struct InspectionDirectoryWalk {
    let descriptor: InspectionDescriptor
    let identities: [InspectionFileStamp]

    init(anchor: InspectionDescriptor, components: [String]) throws {
        var current = anchor
        var identities: [InspectionFileStamp] = []
        for component in components {
            let before = try InspectionFileStamp.child(component, of: current)
            guard !before.isSymlink else { throw LocalSourceInspectionFailure(.symbolicLink) }
            guard before.isDirectory else { throw LocalSourceInspectionFailure(.nonRegularFile) }
            let raw = openat(current.rawValue, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard raw >= 0 else { throw inspectionSystemFailure() }
            let next = InspectionDescriptor(raw)
            let opened = try InspectionFileStamp.descriptor(next)
            guard before.sameObject(as: opened), opened.isDirectory else {
                throw LocalSourceInspectionFailure(.changedDuringRead)
            }
            identities.append(opened)
            current = next
        }
        descriptor = current
        self.identities = identities
    }
}

/// A stable anchor plus the identities of every traversed directory component.
/// Ancestor timestamps are intentionally excluded: unrelated /private/tmp activity
/// does not alter the identity of the user's chosen root.
final class InspectionDirectory {
    private let anchor: InspectionDescriptor
    private let components: [String]
    private let ancestry: [InspectionFileStamp]
    let descriptor: InspectionDescriptor
    private let initialStamp: InspectionFileStamp

    init(isAbsolute: Bool, components: [String]) throws {
        let raw = open(isAbsolute ? "/" : ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard raw >= 0 else { throw inspectionSystemFailure() }
        let anchor = InspectionDescriptor(raw)
        let walk = try InspectionDirectoryWalk(anchor: anchor, components: components)
        self.anchor = anchor
        self.components = components
        ancestry = walk.identities
        descriptor = walk.descriptor
        initialStamp = try InspectionFileStamp.descriptor(descriptor)
    }

    func validate() throws {
        do {
            let walk = try InspectionDirectoryWalk(anchor: anchor, components: components)
            let reopened = try InspectionFileStamp.descriptor(walk.descriptor)
            let retained = try InspectionFileStamp.descriptor(descriptor)
            guard Self.sameIdentities(ancestry, walk.identities),
                  initialStamp == reopened, initialStamp == retained else {
                throw LocalSourceInspectionFailure(.changedDuringRead)
            }
        } catch {
            throw LocalSourceInspectionFailure(.changedDuringRead)
        }
    }

    struct Observation {
        let components: [String]
        let ancestry: [InspectionFileStamp]
        let stamp: InspectionFileStamp
        let byteCount: Int
        let contentSHA256: String
    }

    struct ReadResult {
        let observation: Observation
        let bytes: Data
    }

    /// One bounded, non-recursive directory view. Names remain raw bytes so an
    /// invalid UTF-8 entry cannot be silently changed before policy validation.
    struct DirectoryObservation {
        struct Entry: Equatable {
            let nameBytes: [UInt8]
            let stamp: InspectionFileStamp

            var isDirectory: Bool { stamp.isDirectory }
            var isRegular: Bool { stamp.isRegular }
            var isSymlink: Bool { stamp.isSymlink }
        }

        let components: [String]
        let ancestry: [InspectionFileStamp]
        let directoryStamp: InspectionFileStamp
        let retainedDirectory: InspectionDescriptor
        let entries: [Entry]
        let entryCount: Int
    }

    func observeEntries(
        components: [String], maximumEntries: Int,
        afterEntry: (() -> Void)? = nil
    ) throws -> DirectoryObservation {
        guard maximumEntries >= 0 else { throw LocalSourceInspectionFailure(.limitExceeded) }
        let directory = try InspectionDirectoryWalk(anchor: descriptor, components: components)
        let before = try InspectionFileStamp.descriptor(directory.descriptor)
        guard before.isDirectory,
              directory.identities.last.map({ $0 == before }) ?? components.isEmpty else {
            throw LocalSourceInspectionFailure(.changedDuringRead)
        }

        let rawEnumerationDescriptor = openat(
            directory.descriptor.rawValue, ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard rawEnumerationDescriptor >= 0 else { throw inspectionSystemFailure() }
        guard let stream = fdopendir(rawEnumerationDescriptor) else {
            _ = close(rawEnumerationDescriptor)
            throw inspectionSystemFailure()
        }
        defer { _ = closedir(stream) }

        var entries: [DirectoryObservation.Entry] = []
        while true {
            errno = 0
            guard let rawEntry = readdir(stream) else {
                guard errno == 0 else { throw inspectionSystemFailure() }
                break
            }
            let length = Int(rawEntry.pointee.d_namlen)
            let nameBytes = withUnsafePointer(to: rawEntry.pointee.d_name) { name in
                name.withMemoryRebound(to: UInt8.self, capacity: length) {
                    Array(UnsafeBufferPointer(start: $0, count: length))
                }
            }
            guard nameBytes != [UInt8(ascii: ".")],
                  nameBytes != [UInt8(ascii: "."), UInt8(ascii: ".")] else {
                continue
            }
            guard entries.count < maximumEntries else {
                throw LocalSourceInspectionFailure(.limitExceeded)
            }
            let stamp: InspectionFileStamp
            do {
                stamp = try InspectionFileStamp.child(nameBytes, of: directory.descriptor)
            } catch {
                // readdir already established this raw name. Losing or changing
                // its binding before the no-follow stat is an observed race.
                throw observedEntryBindingFailure(error)
            }
            entries.append(.init(nameBytes: nameBytes, stamp: stamp))
            afterEntry?()
        }

        let after = try InspectionFileStamp.descriptor(directory.descriptor)
        guard before == after else { throw LocalSourceInspectionFailure(.changedDuringRead) }
        entries.sort { $0.nameBytes.lexicographicallyPrecedes($1.nameBytes) }
        let observation = DirectoryObservation(
            components: components,
            ancestry: directory.identities,
            directoryStamp: after,
            retainedDirectory: directory.descriptor,
            entries: entries,
            entryCount: entries.count
        )
        try validateDirectoryBinding(observation)
        return observation
    }

    func validateEntries(
        _ observation: DirectoryObservation, maximumEntries: Int,
        afterEntry: (() -> Void)? = nil
    ) throws {
        do {
            let current = try observeEntries(
                components: observation.components,
                maximumEntries: maximumEntries,
                afterEntry: afterEntry
            )
            guard observation.ancestry == current.ancestry,
                  observation.directoryStamp == current.directoryStamp,
                  observation.entryCount == current.entryCount,
                  observation.entries == current.entries else {
                throw LocalSourceInspectionFailure(.changedDuringRead)
            }
        } catch {
            throw LocalSourceInspectionFailure(.changedDuringRead)
        }
    }

    func validateDirectoryBinding(_ observation: DirectoryObservation) throws {
        do {
            let current = try InspectionDirectoryWalk(anchor: descriptor, components: observation.components)
            let reopened = try InspectionFileStamp.descriptor(current.descriptor)
            let retained = try InspectionFileStamp.descriptor(observation.retainedDirectory)
            guard observation.ancestry == current.identities,
                  observation.directoryStamp == reopened,
                  observation.directoryStamp == retained else {
                throw LocalSourceInspectionFailure(.changedDuringRead)
            }
        } catch {
            throw LocalSourceInspectionFailure(.changedDuringRead)
        }
    }

    func read(
        components: [String], maximumBytes: Int, captureBytes: Bool = false,
        expectedStamp: InspectionFileStamp? = nil, strictByteLimit: Bool = false,
        afterChunk: (() -> Void)? = nil
    ) throws -> ReadResult {
        guard maximumBytes >= 0 else { throw LocalSourceInspectionFailure(.limitExceeded) }
        guard let name = components.last else { throw LocalSourceInspectionFailure(.invalidInputPath) }
        let parent: InspectionDirectoryWalk
        let before: InspectionFileStamp
        do {
            parent = try InspectionDirectoryWalk(
                anchor: descriptor, components: Array(components.dropLast())
            )
            before = try InspectionFileStamp.child(name, of: parent.descriptor)
        } catch {
            throw observedBindingFailure(error, expectedStamp: expectedStamp)
        }
        guard expectedStamp == nil || expectedStamp == before else {
            throw LocalSourceInspectionFailure(.changedDuringRead)
        }
        guard !before.isSymlink else { throw LocalSourceInspectionFailure(.symbolicLink) }
        guard before.isRegular else { throw LocalSourceInspectionFailure(.nonRegularFile) }
        guard before.size >= 0, before.size <= maximumBytes else {
            throw LocalSourceInspectionFailure(.limitExceeded)
        }
        // NONBLOCK prevents a raced-in FIFO from hanging open; fstat still enforces
        // regular-file type before any content read.
        let raw = openat(parent.descriptor.rawValue, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard raw >= 0 else {
            throw observedBindingFailure(inspectionSystemFailure(), expectedStamp: expectedStamp)
        }
        let file = InspectionDescriptor(raw)
        let opened = try InspectionFileStamp.descriptor(file)
        guard before == opened, opened.isRegular else {
            throw LocalSourceInspectionFailure(.changedDuringRead)
        }
        var hasher = SHA256()
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var byteCount = 0
        var interruptedReads = 0
        while true {
            // V2 validation uses the exact prior byte count as its maximum. At
            // that boundary, the descriptor stamp and size prove completion
            // without issuing an extra read beyond the caller's I/O budget.
            let requestCount = strictByteLimit
                ? min(buffer.count, maximumBytes - byteCount)
                : buffer.count
            if requestCount == 0 { break }
            let count = buffer.withUnsafeMutableBytes { storage in
                Darwin.read(file.rawValue, storage.baseAddress, requestCount)
            }
            if count < 0 {
                if errno == EINTR, interruptedReads < 8 {
                    interruptedReads += 1
                    continue
                }
                throw inspectionSystemFailure()
            }
            if count == 0 { break }
            guard count <= maximumBytes - byteCount else {
                throw LocalSourceInspectionFailure(.limitExceeded)
            }
            byteCount += count
            let chunk = Data(buffer.prefix(count))
            hasher.update(data: chunk)
            if captureBytes { bytes.append(chunk) }
            afterChunk?()
        }
        let after = try InspectionFileStamp.descriptor(file)
        let bound: InspectionFileStamp
        do {
            bound = try InspectionFileStamp.child(name, of: parent.descriptor)
        } catch {
            throw observedBindingFailure(error, expectedStamp: expectedStamp)
        }
        guard opened == after, after.size == byteCount,
              after == bound else {
            throw LocalSourceInspectionFailure(.changedDuringRead)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return ReadResult(
            observation: Observation(
                components: components, ancestry: parent.identities, stamp: after,
                byteCount: byteCount, contentSHA256: digest
            ),
            bytes: bytes
        )
    }

    func validate(
        _ observation: Observation, maximumBytes: Int,
        strictByteLimit: Bool = false
    ) throws {
        do {
            let current = try read(
                components: observation.components,
                maximumBytes: maximumBytes,
                strictByteLimit: strictByteLimit
            ).observation
            guard Self.sameIdentities(observation.ancestry, current.ancestry),
                  observation.stamp == current.stamp,
                  observation.byteCount == current.byteCount,
                  observation.contentSHA256 == current.contentSHA256 else {
                throw LocalSourceInspectionFailure(.changedDuringRead)
            }
        } catch {
            throw LocalSourceInspectionFailure(.changedDuringRead)
        }
    }

    private static func sameIdentities(_ lhs: [InspectionFileStamp], _ rhs: [InspectionFileStamp]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.sameObject(as: $1) }
    }
}

private func inspectionSystemFailure() -> LocalSourceInspectionFailure {
    switch errno {
    case ELOOP: LocalSourceInspectionFailure(.symbolicLink)
    case ENOENT: LocalSourceInspectionFailure(.missingInput)
    case ENOTDIR: LocalSourceInspectionFailure(.nonRegularFile)
    default: LocalSourceInspectionFailure(.unreadableInput)
    }
}

/// Once enumeration established a concrete entry, losing or changing its path
/// binding is a concurrent change rather than an initially absent/wrong input.
/// Other failures retain their existing classification, including stable access
/// failures and size limits. A nil expectation preserves the v1 behavior.
private func observedBindingFailure(
    _ error: Error, expectedStamp: InspectionFileStamp?
) -> Error {
    guard expectedStamp != nil else { return error }
    return observedEntryBindingFailure(error)
}

private func observedEntryBindingFailure(_ error: Error) -> Error {
    guard let failure = error as? LocalSourceInspectionFailure,
          failure.code == .missingInput
              || failure.code == .symbolicLink
              || failure.code == .nonRegularFile else {
        return error
    }
    return LocalSourceInspectionFailure(.changedDuringRead)
}
