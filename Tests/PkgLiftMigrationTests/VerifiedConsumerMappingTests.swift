import XCTest
import PkgLiftCore
import PkgLiftRegistry
@testable import PkgLiftMigration

final class VerifiedConsumerMappingTests: XCTestCase {
    private struct ExpectedMapping {
        let name: String
        let version: String
        let lowerVersion: String
        let repository: String
    }

    private let expectedMappings = [
        ExpectedMapping(
            name: "KeychainAccess",
            version: "4.2.2",
            lowerVersion: "4.2.1",
            repository: "https://github.com/kishikawakatsumi/KeychainAccess"
        ),
        ExpectedMapping(
            name: "DeviceKit",
            version: "5.8.0",
            lowerVersion: "5.7.9",
            repository: "https://github.com/devicekit/DeviceKit"
        ),
    ]

    func testVerifiedConsumerMappingsHaveExactRegistryContractAndAdmissionGates() async throws {
        let (sourceLoader, bundledLoader) = try await loadRegistries()

        for expected in expectedMappings {
            let sourceLookup = await sourceLoader.lookup(name: expected.name)
            let bundledLookup = await bundledLoader.lookup(name: expected.name)
            let source = try XCTUnwrap(sourceLookup)
            let bundled = try XCTUnwrap(bundledLookup)

            XCTAssertEqual(source, bundled, expected.name)
            XCTAssertEqual(source.schemaVersion, 2, expected.name)
            XCTAssertEqual(source.pod, PodIdentifier(name: expected.name), expected.name)
            XCTAssertEqual(source.swiftpm.repository, expected.repository, expected.name)
            XCTAssertEqual(source.swiftpm.products, [expected.name], expected.name)
            XCTAssertEqual(source.swiftpm.minimumVersion, expected.version, expected.name)
            XCTAssertEqual(source.swiftpm.supportedConsumerLanguages, [.swift], expected.name)
            XCTAssertEqual(
                source.swiftpm.supportedConsumerPlatforms,
                [SupportedConsumerPlatform(platform: .iOS, minimumDeploymentTarget: "15.0")],
                expected.name
            )
            XCTAssertEqual(source.migration.confidence, .verified, expected.name)
            let unknownSourceSubspec = await sourceLoader.lookup(
                name: expected.name,
                subspec: "Unknown"
            )
            let unknownBundledSubspec = await bundledLoader.lookup(
                name: expected.name,
                subspec: "Unknown"
            )
            XCTAssertNil(unknownSourceSubspec, expected.name)
            XCTAssertNil(unknownBundledSubspec, expected.name)

            assertAutomatic(
                mapping: source,
                expected: expected,
                target: target(platform: "iOS", deploymentTarget: "15.0", languages: [.swift])
            )
            assertAutomatic(
                mapping: source,
                expected: expected,
                target: target(platform: "iOS", deploymentTarget: "16.0", languages: [.swift])
            )

            assertReview(
                mapping: source,
                expected: expected,
                version: expected.lowerVersion,
                target: target(platform: "iOS", deploymentTarget: "15.0", languages: [.swift]),
                reason: .versionBelowMinimum
            )
            assertReview(
                mapping: source,
                expected: expected,
                target: target(platform: "iOS", deploymentTarget: "15.0", languages: [.objectiveC]),
                reason: .targetLanguageUnsupported
            )
            assertReview(
                mapping: source,
                expected: expected,
                target: target(
                    platform: "iOS",
                    deploymentTarget: "15.0",
                    languages: [.swift, .objectiveC]
                ),
                reason: .targetLanguageUnsupported
            )
            assertReview(
                mapping: source,
                expected: expected,
                target: target(platform: "iOS", deploymentTarget: "14.0", languages: [.swift]),
                reason: .targetDeploymentTargetUnsupported
            )
            assertReview(
                mapping: source,
                expected: expected,
                target: target(platform: "macOS", deploymentTarget: "15.0", languages: [.swift]),
                reason: .targetPlatformUnsupported
            )
            assertReview(
                mapping: source,
                expected: expected,
                target: target(platform: "iOS", deploymentTarget: nil, languages: [.swift]),
                reason: .targetDeploymentTargetEvidenceMissing
            )

            var frameworkFeatures = PodfileFeatures()
            frameworkFeatures.useFrameworks = true
            assertReview(
                mapping: source,
                expected: expected,
                target: target(platform: "iOS", deploymentTarget: "15.0", languages: [.swift]),
                reason: .podfileUseFrameworks,
                podfileFeatures: frameworkFeatures
            )

            let unknownSubspec = MigrationClassifier().classify(
                dependency: dependency(
                    name: "\(expected.name)/Unknown",
                    version: expected.version
                ),
                mapping: nil,
                targetInfo: target(
                    platform: "iOS",
                    deploymentTarget: "15.0",
                    languages: [.swift]
                )
            )
            XCTAssertEqual(unknownSubspec.category, .unknown, expected.name)
            XCTAssertTrue(unknownSubspec.reasonDetails.contains {
                $0.code == .registryMappingMissing
            }, expected.name)
        }
    }

    private func loadRegistries() async throws -> (RegistryLoader, RegistryLoader) {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceLoader = RegistryLoader(
            configPaths: [repositoryRoot.appendingPathComponent("Registry")],
            useBundledRegistry: false
        )
        let bundledLoader = RegistryLoader(useBundledRegistry: true)
        try await sourceLoader.load()
        try await bundledLoader.load()
        return (sourceLoader, bundledLoader)
    }

    private func assertAutomatic(
        mapping: RegistryMapping,
        expected: ExpectedMapping,
        target: TargetInfo,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = MigrationClassifier().classify(
            dependency: dependency(name: expected.name, version: expected.version),
            mapping: mapping,
            targetInfo: target
        )
        XCTAssertEqual(result.category, .auto, expected.name, file: file, line: line)
        XCTAssertEqual(
            result.reasonDetails.map(\.code),
            [.verifiedAutomaticMigration],
            expected.name,
            file: file,
            line: line
        )
    }

    private func assertReview(
        mapping: RegistryMapping,
        expected: ExpectedMapping,
        version: String? = nil,
        target: TargetInfo,
        reason: MigrationReasonCode,
        podfileFeatures: PodfileFeatures = PodfileFeatures(),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = MigrationClassifier().classify(
            dependency: dependency(name: expected.name, version: version ?? expected.version),
            mapping: mapping,
            targetInfo: target,
            podfileFeatures: podfileFeatures
        )
        XCTAssertEqual(result.category, .review, expected.name, file: file, line: line)
        XCTAssertTrue(
            result.reasonDetails.contains { $0.code == reason },
            "\(expected.name): \(result.reasonDetails)",
            file: file,
            line: line
        )
    }

    private func dependency(name: String, version: String) -> CocoaPodDependency {
        CocoaPodDependency(
            name: name,
            version: version,
            source: .registry,
            isDirect: true,
            targets: ["App"],
            declarations: [
                PodfileDeclaration(
                    line: 1,
                    scope: .target,
                    scopeName: "App",
                    targetName: "App",
                    source: .registry
                ),
            ],
            targetAttribution: TargetAttribution(status: .exact, targets: ["App"])
        )
    }

    private func target(
        platform: String?,
        deploymentTarget: String?,
        languages: [SourceLanguage]
    ) -> TargetInfo {
        TargetInfo(
            name: "App",
            type: "application",
            platform: platform,
            deploymentTarget: deploymentTarget,
            sourceProfile: TargetSourceProfile(
                languages: languages,
                completeness: .complete
            )
        )
    }
}
