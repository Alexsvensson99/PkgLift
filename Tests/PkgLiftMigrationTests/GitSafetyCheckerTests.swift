import Foundation
import XCTest
@testable import PkgLiftMigration

final class GitSafetyCheckerTests: XCTestCase {
    func testNonGitDirectoryIsIntentionallyAllowed() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try GitSafetyChecker().check(directory: directory)

        XCTAssertFalse(result.isRepository)
        XCTAssertTrue(result.isClean)
        XCTAssertTrue(result.changedFiles.isEmpty)
    }

    func testCleanTemporaryRepository() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try runGit(["init", "--quiet"], in: directory)

        let result = try GitSafetyChecker().check(directory: directory)

        XCTAssertTrue(result.isRepository)
        XCTAssertTrue(result.isClean)
    }

    func testDirtyTemporaryRepositoryReportsChangedFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try runGit(["init", "--quiet"], in: directory)
        try "pod 'Alamofire'".write(
            to: directory.appendingPathComponent("Podfile"),
            atomically: true,
            encoding: .utf8
        )

        let result = try GitSafetyChecker().check(directory: directory)

        XCTAssertTrue(result.isRepository)
        XCTAssertFalse(result.isClean)
        XCTAssertEqual(result.changedFiles, ["Podfile"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftGitSafety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
