import Foundation
import XCTest
@testable import PkgLiftCore

final class ProjectAnalysisTests: XCTestCase {
    func testTargetSourceProfileCanonicalizesLanguages() throws {
        let profile = TargetSourceProfile(
            languages: [.cPlusPlus, .swift, .objectiveC, .swift, .c],
            completeness: .complete
        )

        XCTAssertEqual(profile.languages, [.swift, .objectiveC, .c, .cPlusPlus])

        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(TargetSourceProfile.self, from: encoded)
        XCTAssertEqual(decoded, profile)
    }

    func testTargetInfoDecodesLegacyJSONWithoutSourceProfile() throws {
        let data = Data(
            #"{"name":"App","type":"application","platform":"iOS","deploymentTarget":"16.0"}"#.utf8
        )

        let target = try JSONDecoder().decode(TargetInfo.self, from: data)

        XCTAssertEqual(target.name, "App")
        XCTAssertNil(target.sourceProfile)
    }

    func testPodfileFeaturesDecodeLegacyShapeAndCanonicalizeTypedMarkers() throws {
        let legacy = Data(#"{"hasDynamicRuby":true}"#.utf8)
        let legacyFeatures = try JSONDecoder().decode(PodfileFeatures.self, from: legacy)

        XCTAssertTrue(legacyFeatures.hasDynamicRuby)
        XCTAssertTrue(legacyFeatures.integrationMarkers.isEmpty)

        let current = Data(
            #"{"integrationMarkers":["capacitor","reactNative","capacitor"]}"#.utf8
        )
        let currentFeatures = try JSONDecoder().decode(PodfileFeatures.self, from: current)

        XCTAssertEqual(currentFeatures.integrationMarkers, [.reactNative, .capacitor])
    }

    func testSchemaOneCandidateDecodesWithoutReasonDetailsAndPreservesReasons() throws {
        let legacyCandidate = MigrationCandidate(
            pod: CocoaPodDependency(name: "LegacyPod", isDirect: true),
            classification: .review,
            reasons: ["Legacy free-form reason"]
        )
        let data = try JSONEncoder().encode(legacyCandidate)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNil(object["reasonDetails"])

        let decoded = try JSONDecoder().decode(MigrationCandidate.self, from: data)

        XCTAssertEqual(decoded.reasons, ["Legacy free-form reason"])
        XCTAssertNil(decoded.reasonDetails)
        XCTAssertNil(decoded.pod.sourceProvenance)
    }

    func testTypedReasonDetailsAreAdditiveAndKeepLegacyMessagesUnchanged() throws {
        let detail = MigrationReason(
            code: .registryMappingMissing,
            message: "No registry mapping",
            remediation: "Add an exact verified registry mapping."
        )
        let candidate = MigrationCandidate(
            pod: CocoaPodDependency(name: "UnknownPod", isDirect: true),
            classification: .unknown,
            reasons: [detail.message],
            reasonDetails: [detail]
        )

        let data = try JSONEncoder().encode(candidate)
        let decoded = try JSONDecoder().decode(MigrationCandidate.self, from: data)

        XCTAssertEqual(decoded.reasons, ["No registry mapping"])
        XCTAssertEqual(decoded.reasonDetails, [detail])
        XCTAssertEqual(MigrationPlan.schemaVersion, 1)
        XCTAssertEqual(ProjectAnalysis.schemaVersion, 1)
    }

    func testSchemaOnePlanEntryDecodesWithoutReasonDetails() throws {
        let entry = MigrationPlanEntry(
            podName: "LegacyPod",
            currentVersion: "1.2.3",
            classification: .review,
            actions: [.manual(description: "Review")],
            reasons: ["Legacy plan reason"]
        )
        let data = try JSONEncoder().encode(entry)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNil(object["reasonDetails"])

        let decoded = try JSONDecoder().decode(MigrationPlanEntry.self, from: data)

        XCTAssertEqual(decoded.reasons, ["Legacy plan reason"])
        XCTAssertNil(decoded.reasonDetails)
        XCTAssertNil(decoded.sourceProvenance)
    }
}
