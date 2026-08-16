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
}
