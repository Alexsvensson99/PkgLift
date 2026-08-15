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
}
