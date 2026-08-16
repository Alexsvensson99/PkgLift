import XCTest
@testable import PkgLiftCLI

final class PortableJSONOptionTests: XCTestCase {
    func testAnalyzeAcceptsPortableJSON() throws {
        let command = try AnalyzeCommand.parse(["--portable-json"])

        XCTAssertTrue(command.portableJSON)
        XCTAssertFalse(command.common.json)
    }

    func testPlanAcceptsPortableJSON() throws {
        let command = try PlanCommand.parse(["--portable-json"])

        XCTAssertTrue(command.portableJSON)
        XCTAssertFalse(command.common.json)
    }

    func testAnalyzeRejectsJSONFlagConflict() {
        XCTAssertThrowsError(try AnalyzeCommand.parse(["--json", "--portable-json"])) { error in
            XCTAssertTrue(AnalyzeCommand.message(for: error).contains("mutually exclusive"))
        }
    }

    func testPlanRejectsJSONFlagConflict() {
        XCTAssertThrowsError(try PlanCommand.parse(["--json", "--portable-json"])) { error in
            XCTAssertTrue(PlanCommand.message(for: error).contains("mutually exclusive"))
        }
    }
}
