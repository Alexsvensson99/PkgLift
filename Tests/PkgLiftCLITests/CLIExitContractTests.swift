import ArgumentParser
import XCTest
@testable import PkgLiftCLI

final class CLIExitContractTests: XCTestCase {
    func testUsageErrorsHaveUsageStatusAndHelpSucceeds() throws {
        for arguments in [
            ["analyze", "--json", "--portable-json"],
            ["analyze", "--fail-on", "invalid-policy"],
            ["podspec", "inspect"],
        ] {
            XCTAssertThrowsError(try PkgLift.parseAsRoot(arguments)) { error in
                XCTAssertEqual(PkgLift.exitCode(for: error).rawValue, 64, "\(arguments)")
            }
        }
        // parseAsRoot returns a HelpCommand; typed parse exposes its clean help exit.
        XCTAssertThrowsError(try PkgLift.parse(["--help"])) { error in
            XCTAssertEqual(PkgLift.exitCode(for: error).rawValue, 0)
        }
    }

    func testAnalysisPolicyFailureHasGeneralErrorStatus() {
        let error = AnalysisError.failurePolicyMatched(policy: .nonAuto, dependencyCount: 1)
        XCTAssertEqual(PkgLift.exitCode(for: error).rawValue, 1)
    }
}
