import Foundation
import XCTest
@testable import PkgLiftCore

final class JSONContractCompatibilityTests: XCTestCase {
    func testSchemaOneIgnoresUnknownFieldsButRejectsUnknownEnumValues() throws {
        let analysis = makeAnalysis()
        var analysisObject = try jsonObject(for: analysis)
        analysisObject["futureTopLevel"] = ["enabled": true]
        var project = try XCTUnwrap(analysisObject["project"] as? [String: Any])
        project["futureNestedField"] = "ignored"
        analysisObject["project"] = project

        let decodedAnalysis = try decode(ProjectAnalysis.self, from: analysisObject)
        XCTAssertEqual(decodedAnalysis.project.projectPath, "/tmp/App.xcodeproj")
        XCTAssertEqual(decodedAnalysis.candidates.first?.classification, .review)

        let plan = MigrationPlan(
            projectPath: "/tmp/App.xcodeproj",
            entries: [makePlanEntry()],
            issues: [],
            readinessScore: 50
        )
        var planObject = try jsonObject(for: plan)
        planObject["futureTopLevel"] = ["version": 2]
        var entries = try XCTUnwrap(planObject["entries"] as? [[String: Any]])
        entries[0]["futureNestedField"] = ["value": "ignored"]
        planObject["entries"] = entries

        let decodedPlan = try decode(MigrationPlan.self, from: planObject)
        XCTAssertEqual(decodedPlan.entries.first?.podName, "LegacyPod")

        let verification = VerificationResult(
            passed: true,
            checks: [
                VerificationCheck(
                    name: "structure",
                    description: "Project structure",
                    passed: true
                ),
            ]
        )
        var verificationObject = try jsonObject(for: verification)
        verificationObject["futureTopLevel"] = true
        var checks = try XCTUnwrap(verificationObject["checks"] as? [[String: Any]])
        checks[0]["futureNestedField"] = 1
        verificationObject["checks"] = checks

        let decodedVerification = try decode(VerificationResult.self, from: verificationObject)
        XCTAssertTrue(decodedVerification.passed)
        XCTAssertEqual(decodedVerification.checks.first?.name, "structure")

        var unknownClassification = try jsonObject(for: analysis)
        var classificationCandidates = try XCTUnwrap(
            unknownClassification["candidates"] as? [[String: Any]]
        )
        classificationCandidates[0]["classification"] = "FUTURE"
        unknownClassification["candidates"] = classificationCandidates
        assertDecodingError(ProjectAnalysis.self, from: unknownClassification)

        var unknownReason = try jsonObject(for: analysis)
        var reasonCandidates = try XCTUnwrap(unknownReason["candidates"] as? [[String: Any]])
        var reasonDetails = try XCTUnwrap(
            reasonCandidates[0]["reasonDetails"] as? [[String: Any]]
        )
        reasonDetails[0]["code"] = "future_reason"
        reasonCandidates[0]["reasonDetails"] = reasonDetails
        unknownReason["candidates"] = reasonCandidates
        assertDecodingError(ProjectAnalysis.self, from: unknownReason)

        var unknownIntegration = try jsonObject(for: analysis)
        unknownIntegration["detectedIntegrations"] = ["futureIntegration"]
        assertDecodingError(ProjectAnalysis.self, from: unknownIntegration)
    }

    private func makeAnalysis() -> ProjectAnalysis {
        let reason = MigrationReason(
            code: .registryMappingMissing,
            message: "No registry mapping"
        )
        return ProjectAnalysis(
            project: ProjectInfo(projectPath: "/tmp/App.xcodeproj"),
            cocoaPods: CocoaPodsState(),
            swiftPM: SwiftPMState(),
            candidates: [
                MigrationCandidate(
                    pod: CocoaPodDependency(name: "LegacyPod", isDirect: true),
                    classification: .review,
                    reasons: [reason.message],
                    reasonDetails: [reason]
                ),
            ],
            issues: [],
            readinessScore: 50,
            detectedIntegrations: [.carthage]
        )
    }

    private func makePlanEntry() -> MigrationPlanEntry {
        MigrationPlanEntry(
            podName: "LegacyPod",
            currentVersion: "1.2.3",
            classification: .review,
            actions: [.manual(description: "Review")],
            reasons: ["No registry mapping"]
        )
    }

    private func jsonObject<T: Encodable>(for value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any]
        )
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from object: [String: Any]
    ) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func assertDecodingError<T: Decodable>(
        _ type: T.Type,
        from object: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try decode(type, from: object),
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(error is DecodingError, "Unexpected error: \(error)", file: file, line: line)
        }
    }
}
