import XCTest
@testable import PkgLiftCore

final class ProcessRunnerTests: XCTestCase {
    func testLargeStdoutAndStderrDoNotDeadlock() throws {
        let script = "print STDOUT qq{x} x 200000; print STDERR qq{y} x 200000"
        let result = try ProcessRunner().run(
            executable: "/usr/bin/perl",
            arguments: ["-e", script]
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout.count, 200_000)
        XCTAssertEqual(result.stderr.count, 200_000)
    }

    func testArgumentsArePassedWithoutShellInterpretation() throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftShellMarker-\(UUID().uuidString)")
        let untrusted = "$(touch \(marker.path)); value with spaces"
        let result = try ProcessRunner().run(
            executable: "/usr/bin/printf",
            arguments: ["%s", untrusted]
        )

        XCTAssertEqual(result.stdout, untrusted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }
}
