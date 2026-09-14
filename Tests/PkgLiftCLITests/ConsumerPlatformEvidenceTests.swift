import XCTest
import PkgLiftCore
@testable import PkgLiftCLI

final class ConsumerPlatformEvidenceTests: XCTestCase {
    private let iOS15 = [
        SupportedConsumerPlatform(platform: .iOS, minimumDeploymentTarget: "15.0"),
    ]

    func testOmittedPlatformEvidencePreservesLegacyCompatibility() {
        XCTAssertTrue(hasCompatiblePlatformEvidence(targetInfo: nil, supportedPlatforms: nil))
    }

    func testCompatiblePlatformEvidenceRequiresKnownMatchingEnvironment() {
        XCTAssertTrue(hasCompatiblePlatformEvidence(
            targetInfo: target(platform: "iOS", deploymentTarget: "15.0"),
            supportedPlatforms: iOS15
        ))
        XCTAssertTrue(hasCompatiblePlatformEvidence(
            targetInfo: target(platform: "iOS", deploymentTarget: "16.0"),
            supportedPlatforms: iOS15
        ))
        XCTAssertFalse(hasCompatiblePlatformEvidence(
            targetInfo: target(platform: "iOS", deploymentTarget: "14.9"),
            supportedPlatforms: iOS15
        ))
        XCTAssertFalse(hasCompatiblePlatformEvidence(
            targetInfo: target(platform: "macOS", deploymentTarget: "15.0"),
            supportedPlatforms: iOS15
        ))
        XCTAssertFalse(hasCompatiblePlatformEvidence(
            targetInfo: target(platform: nil, deploymentTarget: nil),
            supportedPlatforms: iOS15
        ))
    }

    private func target(platform: String?, deploymentTarget: String?) -> TargetInfo {
        TargetInfo(
            name: "App",
            type: "application",
            platform: platform,
            deploymentTarget: deploymentTarget,
            sourceProfile: TargetSourceProfile(languages: [.swift], completeness: .complete)
        )
    }
}
