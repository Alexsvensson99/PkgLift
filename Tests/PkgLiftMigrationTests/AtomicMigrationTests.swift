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
    }

    private enum TestFailure: Error {
        case expected
    }
}
