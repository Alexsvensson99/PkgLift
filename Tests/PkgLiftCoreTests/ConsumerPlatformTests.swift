import XCTest
@testable import PkgLiftCore

final class ConsumerPlatformTests: XCTestCase {
    func testDeploymentTargetComparisonPadsOmittedComponents() throws {
        let fifteen = try XCTUnwrap(DeploymentTargetVersion(rawValue: "15"))
        let fifteenZero = try XCTUnwrap(DeploymentTargetVersion(rawValue: "15.0"))
        let fifteenZeroOne = try XCTUnwrap(DeploymentTargetVersion(rawValue: "15.0.1"))

        XCTAssertEqual(fifteen, fifteenZero)
        XCTAssertLessThan(fifteenZero, fifteenZeroOne)
    }

    func testDeploymentTargetParserRejectsAmbiguousForms() {
        for value in [
            "", ".", "15.", ".15", "15..0", "15.0.0.0", " 15.0",
            "15.0 ", "015.0", "15.00", "+15.0", "v15.0", "15.0-beta",
            "999999999999999999999999999999.0",
        ] {
            XCTAssertNil(
                DeploymentTargetVersion(rawValue: value),
                "Expected \(value) to be rejected"
            )
        }
    }
}
