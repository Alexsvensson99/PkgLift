import XCTest
@testable import PkgLiftCLI

final class VerifyCommandOptionTests: XCTestCase {
    func testParsesExplicitBuildVerificationOptions() throws {
        let command = try VerifyCommand.parse([
            "--path", "/tmp/My Project",
            "--build",
            "--scheme", "MyApp",
            "--configuration", "Release",
            "--destination", "platform=iOS Simulator,name=iPhone 16 Pro",
            "--sdk", "iphonesimulator",
            "--derived-data-path", ".pkglift/Derived Data",
        ])

        XCTAssertTrue(command.build)
        XCTAssertEqual(command.scheme, "MyApp")
        XCTAssertEqual(command.configuration, "Release")
        XCTAssertEqual(command.destination, "platform=iOS Simulator,name=iPhone 16 Pro")
        XCTAssertEqual(command.sdk, "iphonesimulator")
        XCTAssertEqual(command.derivedDataPath, ".pkglift/Derived Data")
    }

    func testRelativeDerivedDataPathResolvesAgainstProjectRoot() throws {
        XCTAssertEqual(
            try VerifyCommand.resolveDerivedDataPath(
                ".pkglift/Derived Data",
                rootPath: "/tmp/My Project"
            ),
            "/tmp/My Project/.pkglift/Derived Data"
        )
    }

    func testAbsoluteDerivedDataPathRemainsAbsolute() throws {
        XCTAssertEqual(
            try VerifyCommand.resolveDerivedDataPath(
                "/tmp/Shared Derived Data",
                rootPath: "/tmp/My Project"
            ),
            "/tmp/Shared Derived Data"
        )
    }

    func testRelativeDerivedDataPathCannotEscapeProjectRoot() {
        XCTAssertThrowsError(
            try VerifyCommand.resolveDerivedDataPath(
                "../Shared Derived Data",
                rootPath: "/tmp/My Project"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("escapes project root"))
        }
    }

    func testRelativeDerivedDataPathCannotEscapeThroughSymlink() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("PkgLiftDerivedRoot-\(UUID().uuidString)", isDirectory: true)
        let outside = fileManager.temporaryDirectory
            .appendingPathComponent("PkgLiftDerivedOutside-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.removeItem(at: outside)
        }
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("LinkedDerivedData"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(
            try VerifyCommand.resolveDerivedDataPath(
                "LinkedDerivedData/Build",
                rootPath: root.path
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("escapes project root"))
        }
    }

    func testRelativeDerivedDataPathRejectsDanglingSymlink() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("PkgLiftDerivedRoot-\(UUID().uuidString)", isDirectory: true)
        let missingTarget = fileManager.temporaryDirectory
            .appendingPathComponent("PkgLiftMissingDerived-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("DanglingDerivedData"),
            withDestinationURL: missingTarget
        )

        XCTAssertThrowsError(
            try VerifyCommand.resolveDerivedDataPath(
                "DanglingDerivedData/Build",
                rootPath: root.path
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("dangling symbolic link"))
        }
    }

    func testBuildOptionsRequireBuildFlag() async throws {
        var command = try VerifyCommand.parse([
            "--path", "/tmp/My Project",
            "--scheme", "MyApp",
        ])

        do {
            try await command.run()
            XCTFail("Expected build options without --build to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("require --build"))
        }
    }
}
