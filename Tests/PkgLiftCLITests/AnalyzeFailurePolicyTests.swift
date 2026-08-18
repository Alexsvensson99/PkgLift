import Foundation
import XCTest
import PkgLiftCore
@testable import PkgLiftCLI

final class AnalyzeFailurePolicyTests: XCTestCase {
    func testAnalyzeParsesEveryFailurePolicy() throws {
        XCTAssertEqual(try AnalyzeCommand.parse(["--fail-on", "blocked"]).failOn, .blocked)
        XCTAssertEqual(try AnalyzeCommand.parse(["--fail-on", "unresolved"]).failOn, .unresolved)
        XCTAssertEqual(try AnalyzeCommand.parse(["--fail-on", "non-auto"]).failOn, .nonAuto)
        XCTAssertThrowsError(try AnalyzeCommand.parse(["--fail-on", "review"]))
    }

    func testFailurePoliciesUseOnlyDirectDependenciesAsStrictnessLadder() {
        let candidates = [
            candidate(name: "Automatic", classification: .auto),
            candidate(name: "Review", classification: .review),
            candidate(name: "Blocked", classification: .blocked),
            candidate(name: "Unknown", classification: .unknown),
            candidate(name: "TransitiveBlocked", classification: .blocked, isDirect: false),
        ]

        XCTAssertEqual(
            AnalyzeFailurePolicy.blocked.failingDirectCandidates(in: candidates).map(\.pod.name),
            ["Blocked"]
        )
        XCTAssertEqual(
            AnalyzeFailurePolicy.unresolved.failingDirectCandidates(in: candidates).map(\.pod.name),
            ["Blocked", "Unknown"]
        )
        XCTAssertEqual(
            AnalyzeFailurePolicy.nonAuto.failingDirectCandidates(in: candidates).map(\.pod.name),
            ["Review", "Blocked", "Unknown"]
        )
    }

    func testStandardAndPortableJSONRemainValidWhenFailurePolicyMatches() throws {
        let unknown = candidate(name: "Unknown", classification: .unknown)
        let analysis = ProjectAnalysis(
            project: ProjectInfo(projectPath: "/private/project/App.xcodeproj", targets: []),
            cocoaPods: CocoaPodsState(
                directDependencies: [unknown.pod],
                hasPodfile: true
            ),
            swiftPM: SwiftPMState(),
            candidates: [unknown],
            issues: [],
            readinessScore: 0
        )

        XCTAssertEqual(
            AnalyzeFailurePolicy.unresolved.failingDirectCandidates(in: analysis.candidates).count,
            1
        )
        for portable in [false, true] {
            let output = try AnalyzeCommand.jsonOutput(for: analysis, portable: portable)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
            )
            XCTAssertEqual(object["schemaVersion"] as? Int, 1)
            if portable {
                let marker = try XCTUnwrap(object["portableOutput"] as? [String: Any])
                XCTAssertEqual(marker["version"] as? Int, 1)
            } else {
                XCTAssertNil(object["portableOutput"])
            }
        }
    }

    private func candidate(
        name: String,
        classification: MigrationClassification,
        isDirect: Bool = true
    ) -> MigrationCandidate {
        MigrationCandidate(
            pod: CocoaPodDependency(name: name, isDirect: isDirect),
            classification: classification,
            reasons: ["Reason"],
            reasonDetails: [MigrationReason(code: .unspecified, message: "Reason")]
        )
    }
}
