import XCTest
@testable import PkgLiftCore

final class SemanticVersionTests: XCTestCase {
    func testParsesAndComparesStableThreeComponentVersions() throws {
        let lower = try XCTUnwrap(SemanticVersion(rawValue: "5.1.0"))
        let patch = try XCTUnwrap(SemanticVersion(rawValue: "5.1.1"))
        let minor = try XCTUnwrap(SemanticVersion(rawValue: "5.2.0"))
        let major = try XCTUnwrap(SemanticVersion(rawValue: "6.0.0"))

        XCTAssertEqual(lower.description, "5.1.0")
        XCTAssertLessThan(lower, patch)
        XCTAssertLessThan(patch, minor)
        XCTAssertLessThan(minor, major)
    }

    func testRejectsAmbiguousOrUnstableVersions() {
        [
            "5", "5.1", "5.1.0.0", "5.1.0-beta.1", "5.1.0+build",
            "05.1.0", "5.01.0", "5.1.00", " 5.1.0", "5.1.0 ",
            "5..0", "v5.1.0", "",
        ].forEach { value in
            XCTAssertNil(SemanticVersion(rawValue: value), "Expected \(value) to be rejected")
        }
    }
}
