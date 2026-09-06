import Foundation
import XCTest
@testable import PkgLiftMigration

final class AtomicMigrationTests: XCTestCase {
    func testFailureRestoresPodfileAndXcodeProjectDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftAtomic-\(UUID().uuidString)")
        let podfile = root.appendingPathComponent("Podfile")
        let project = root.appendingPathComponent("App.xcodeproj")
        let pbxproj = project.appendingPathComponent("project.pbxproj")
        let backup = root.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "original podfile".write(to: podfile, atomically: true, encoding: .utf8)
        try "original project".write(to: pbxproj, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try AtomicMigration().perform(
            files: [podfile, project],
            backupDir: backup
        ) {
            try "changed podfile".write(to: podfile, atomically: true, encoding: .utf8)
            try "changed project".write(to: pbxproj, atomically: true, encoding: .utf8)
            throw TestFailure.expected
        })

        XCTAssertEqual(try String(contentsOf: podfile), "original podfile")
        XCTAssertEqual(try String(contentsOf: pbxproj), "original project")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("migration-in-progress").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appendingPathComponent(".pkglift-completed.json").path))
        XCTAssertNoThrow(try AtomicMigration.checkForIncompleteMigration(backupDir: backup))
    }

    func testOccupiedBackupWithoutCompletedReceiptFailsClosedWithoutOverwrite() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let podfile = root.appendingPathComponent("Podfile")
        let backup = root.appendingPathComponent("backup")
        let preserved = backup.appendingPathComponent("preserved")
        try "original".write(to: podfile, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        try "recovery evidence".write(to: preserved, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try AtomicMigration().perform(files: [podfile], backupDir: backup) {
            XCTFail("Action must not run with ambiguous recovery state")
        }) { error in
            XCTAssertTrue(error.localizedDescription.contains("unsafe or incomplete"))
        }
        XCTAssertEqual(try String(contentsOf: preserved), "recovery evidence")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("migration-in-progress").path))
    }

    func testCancellationDuringBackupCleansNewStateWithoutChangingOriginals() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let podfile = root.appendingPathComponent("Podfile")
        let project = root.appendingPathComponent("App.xcodeproj")
        let pbxproj = project.appendingPathComponent("project.pbxproj")
        let backup = root.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        try "original podfile".write(to: podfile, atomically: true, encoding: .utf8)
        try "original project".write(to: pbxproj, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try AtomicMigration().perform(
            files: [podfile, project],
            backupDir: backup,
            checkCancellation: {
                if FileManager.default.fileExists(atPath: backup.appendingPathComponent("Podfile").path) {
                    throw TestFailure.cancelled
                }
            }
        ) {
            XCTFail("Action must not run after cancellation during backup")
        }) { error in
            XCTAssertEqual(error as? TestFailure, .cancelled)
        }
        XCTAssertEqual(try String(contentsOf: podfile), "original podfile")
        XCTAssertEqual(try String(contentsOf: pbxproj), "original project")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("migration-in-progress").path))
    }

    func testActiveMarkerWinsOverOtherwiseCompletedBackup() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let backup = root.appendingPathComponent("backup")
        let marker = root.appendingPathComponent("migration-in-progress")
        let podfile = root.appendingPathComponent("Podfile")
        try Data("original".utf8).write(to: podfile)
        try AtomicMigration().perform(files: [podfile], backupDir: backup) {}
        try "corrupt or interrupted".write(to: marker, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try AtomicMigration.checkForIncompleteMigration(backupDir: backup)) { error in
            XCTAssertTrue(error.localizedDescription.contains("incomplete migration"))
        }
        XCTAssertEqual(try String(contentsOf: marker), "corrupt or interrupted")
    }

    func testSuccessfulMigrationFinalizesMarkerAndCompletedBackupCanBeReused() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let podfile = root.appendingPathComponent("Podfile")
        let backup = root.appendingPathComponent("backup")
        let marker = root.appendingPathComponent("migration-in-progress")
        try Data("original".utf8).write(to: podfile)
        for (before, after) in [("original", "first migration"), ("first migration", "second migration")] {
            try AtomicMigration().perform(files: [podfile], backupDir: backup) {
                XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: marker)) as? [String: Any])
                XCTAssertEqual(Set(json.keys), ["schemaVersion", "files", "backupDirectory"])
                XCTAssertEqual(json["files"] as? [String], [podfile.resolvingSymlinksInPath().path])
                try Data(after.utf8).write(to: podfile)
            }
            XCTAssertEqual(try Data(contentsOf: podfile), Data(after.utf8))
            XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Podfile")), Data(before.utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
            XCTAssertNoThrow(try AtomicMigration.checkForIncompleteMigration(backupDir: backup))
        }
    }

    func testConcurrentAttemptCannotReplaceOwnedMarkerOrBackup() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let podfile = root.appendingPathComponent("Podfile")
        let backup = root.appendingPathComponent("backup")
        let marker = root.appendingPathComponent("migration-in-progress")
        try Data("original".utf8).write(to: podfile)
        try AtomicMigration().perform(files: [podfile], backupDir: backup) {
            let ownedMarker = try Data(contentsOf: marker)
            try Data("partial migration".utf8).write(to: podfile)
            XCTAssertThrowsError(try AtomicMigration().perform(files: [podfile], backupDir: backup) {
                XCTFail("A second owner must never enter its action")
            }) { error in
                guard case AtomicMigration.MigrationError.incompleteMigration = error else {
                    return XCTFail("Expected exclusive transaction refusal: \(error)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: marker), ownedMarker)
            XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Podfile")), Data("original".utf8))
        }
    }

    func testRollbackFailureStillAttemptsOtherOriginalAndPreservesRecoveryState() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let podfile = root.appendingPathComponent("Podfile")
        let project = root.appendingPathComponent("App.xcodeproj")
        let pbxproj = project.appendingPathComponent("project.pbxproj")
        let backup = root.appendingPathComponent("backup")
        let marker = root.appendingPathComponent("migration-in-progress")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        try Data("original Podfile".utf8).write(to: podfile)
        try Data("original project".utf8).write(to: pbxproj)
        XCTAssertThrowsError(try AtomicMigration().perform(files: [podfile, project], backupDir: backup) {
            try Data("changed Podfile".utf8).write(to: podfile)
            try Data("changed project".utf8).write(to: pbxproj)
            // Deterministically simulate a lost backup during a storage fault.
            try FileManager.default.removeItem(at: backup.appendingPathComponent("Podfile"))
            throw TestFailure.expected
        }) { error in
            guard case AtomicMigration.MigrationError.rollbackFailed(let underlying, let failures) = error else {
                return XCTFail("Must report incomplete rollback: \(error)")
            }
            XCTAssertEqual(underlying as? TestFailure, .expected)
            XCTAssertEqual(failures.map(\.path), [podfile.resolvingSymlinksInPath().path])
        }
        XCTAssertEqual(try Data(contentsOf: pbxproj), Data("original project".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.appendingPathComponent(".pkglift-completed.json").path))
        XCTAssertThrowsError(try AtomicMigration.checkForIncompleteMigration(backupDir: backup))
    }

    func testMissingRequiredOriginalCreatesNoTransactionState() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let backup = root.appendingPathComponent("backup")
        XCTAssertThrowsError(try AtomicMigration().perform(files: [root.appendingPathComponent("missing")], backupDir: backup) {
            XCTFail("Required originals must be validated before backup creation")
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("migration-in-progress").path))
    }

    func testCompletedBackupForDifferentOriginalCannotBeReplaced() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let backup = root.appendingPathComponent("backup")
        let first = root.appendingPathComponent("Podfile")
        let second = root.appendingPathComponent("OtherPodfile")
        try Data("original".utf8).write(to: first)
        try Data("other".utf8).write(to: second)
        try AtomicMigration().perform(files: [first], backupDir: backup) {}
        let receipt = try Data(contentsOf: backup.appendingPathComponent(".pkglift-completed.json"))
        XCTAssertThrowsError(try AtomicMigration().perform(files: [second], backupDir: backup) {
            XCTFail("A different migration context must not replace this backup")
        })
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Podfile")), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent(".pkglift-completed.json")), receipt)
    }

    func testDanglingMarkerSymlinkCannotBeIgnoredOrReplaced() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("migration-in-progress")
        let target = root.appendingPathComponent("nonexistent")
        try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: target)
        XCTAssertThrowsError(try AtomicMigration.checkForIncompleteMigration(backupDir: root.appendingPathComponent("backup")))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: marker.path), target.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftAtomic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private enum TestFailure: Error, Equatable {
        case expected
        case cancelled
    }
}
