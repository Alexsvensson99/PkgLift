import CryptoKit
import Foundation
import Testing
@testable import PkgLiftCocoaPods

@Suite("Podspec v0.5 Release Gate Tests")
struct PodspecV05ReleaseGateTests {
    @Test("Pin fixture bytes and exact assessment outcomes and paths")
    func pinnedFixtureMatrix() throws {
        for fixture in fixtureExpectations() {
            let data = try fixtureData(named: fixture.resourceName)
            #expect(sha256(data) == fixture.sha256)

            let assessment = try assess(data)
            #expect(assessment.schemaVersion == 1)
            #expect(assessment.cocoaPodsProfile == .cocoaPodsCore1_17_0)
            #expect(assessment.swiftPMProfile == .swiftToolsVersion6_0)
            #expect(assessment.outcome == fixture.outcome)
            #expect(assessment.reasons == fixture.reasons)
        }
    }

    @Test("Cover every outcome and reason code, including malformed-model fail-closed")
    func completeOutcomeAndReasonCoverage() throws {
        let compatible = try assess(Data(#"{"name":"Compatible","version":"5.0.0"}"#.utf8))
        #expect(compatible.outcome == .declarationCompatible)
        #expect(compatible.reasons.isEmpty)

        let malformed = try malformedModelAssessment()
        #expect(malformed.outcome == .indeterminate)
        #expect(malformed.reasons == [reason(.incompleteModeledSemantic, "")])

        var outcomeRawValues: Set<String> = [compatible.outcome.rawValue]
        var codes = Set(malformed.reasons.map(\.code))
        for fixture in fixtureExpectations() {
            let assessment = try assessFixture(named: fixture.resourceName)
            outcomeRawValues.insert(assessment.outcome.rawValue)
            codes.formUnion(assessment.reasons.map(\.code))
        }

        #expect(outcomeRawValues == Set(
            PodspecSwiftPMAssessment.Outcome.allCases.map(\.rawValue)
        ))
        #expect(codes.count == 28)
        #expect(codes == Set(PodspecSwiftPMAssessmentReason.Code.allCases))
    }

    @Test("Keep fixture assessments deterministic and Codable round-trippable")
    func deterministicCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        for fixture in fixtureExpectations() {
            let first = try assessFixture(named: fixture.resourceName)
            let second = try assessFixture(named: fixture.resourceName)
            #expect(first == second)

            let firstBytes = try encoder.encode(first)
            let secondBytes = try encoder.encode(second)
            #expect(firstBytes == secondBytes)
            #expect(sha256(firstBytes) == fixture.assessmentSHA256)

            let decoded = try JSONDecoder().decode(
                PodspecSwiftPMAssessment.self,
                from: firstBytes
            )
            #expect(decoded == first)
            let roundTripBytes = try encoder.encode(decoded)
            #expect(roundTripBytes == firstBytes)
        }
    }

    @Test("Exclude fixture secrets, dynamic keys, and local paths from artifacts")
    func fixturePrivacyBoundary() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        var artifacts = ""
        for fixture in fixtureExpectations() {
            let assessment = try assessFixture(named: fixture.resourceName)
            artifacts += String(decoding: try encoder.encode(assessment), as: UTF8.self)
        }

        let privateFragments = [
            "private-token-71",
            "PrivateBundle71",
            "PrivateDependency71",
            "PrivateModule71",
            "future_private_token_71",
            "token-71@example.invalid",
            "/Users/private-71",
            "PrivateCore71",
            "PrivateWeakKit71",
            "PRIVATE_TOKEN_71",
            "secret-value-71",
            "PRIVATE_BUILD_KEY_71",
            "GeneratedSecret71",
            "Secret.framework",
            "libSecret.a",
        ]
        for fragment in privateFragments {
            #expect(!artifacts.contains(fragment))
        }

        #expect(artifacts.contains(#""evidencePath":"/unsupportedFields/0""#))
        #expect(artifacts.contains(
            #""evidencePath":"/subspecs/0/dependencies/0""#
        ))
        #expect(artifacts.contains(#""evidencePath":"/xcconfig/0""#))
        #expect(artifacts.contains(#""evidencePath":"/ios/source_files""#))
        #expect(artifacts.contains(#""evidencePath":"/subspecs/0/resources""#))
        #expect(artifacts.contains(
            #""evidencePath":"/subspecs/0/ios/weak_frameworks/0""#
        ))
    }

    private func fixtureExpectations() -> [FixtureExpectation] {
        [
            FixtureExpectation(
                resourceName: "AssessmentGenerated-5.0.0.podspec",
                sha256: "dce61554ee3c126aa8ead34370772e0c38ad902f950fe4253e8411838f3b9dc3",
                assessmentSHA256: "c422c60d7b5883230b81252a5854ba910c74f247f317523860a8555e2b27ea24",
                outcome: .requiresGeneratedMetadata,
                reasons: [
                    reason(.defaultSubspecRequiresGeneratedMetadata, "/default_subspecs"),
                    reason(.dependencyRequiresGeneratedMetadata, "/dependencies/0"),
                    reason(.fileExclusionRequiresGeneratedMetadata, "/exclude_files/0"),
                    reason(.generatedModuleMapRequiresGeneratedMetadata, "/module_map"),
                    reason(.headerLayoutRequiresGeneratedMetadata, "/header_dir"),
                    reason(.headerSelectionRequiresGeneratedMetadata, "/public_header_files"),
                    reason(.linkageModeRequiresGeneratedMetadata, "/static_framework"),
                    reason(.linkerSettingRequiresGeneratedMetadata, "/frameworks/0"),
                    reason(.moduleNameRequiresGeneratedMetadata, "/module_name"),
                    reason(.platformRequiresGeneratedMetadata, "/platforms/ios"),
                    reason(.resourceBundleRequiresGeneratedMetadata, "/resource_bundles"),
                    reason(.resourceSelectionRequiresGeneratedMetadata, "/resources"),
                    reason(.sourceSelectionRequiresGeneratedMetadata, "/source_files"),
                ]
            ),
            FixtureExpectation(
                resourceName: "AssessmentIndeterminate-5.0.0.podspec",
                sha256: "010645068c5789f41ad7d687345bc18b49e469a8297ff31cae44b30896e40e5f",
                assessmentSHA256: "adfa74dc73470899120051dbf61b6417c384b4c29a8c0ddfddd39293657356f5",
                outcome: .indeterminate,
                reasons: [
                    reason(.customModuleMapRequiresInspection, "/module_map"),
                    reason(.deferredCocoaPodsSemantic, "/unsupportedFields/1"),
                    reason(.deferredCocoaPodsSemantic, "/unsupportedFields/2"),
                    reason(.deferredCocoaPodsSemantic, "/unsupportedFields/3"),
                    reason(.deferredCocoaPodsSemantic, "/unsupportedFields/4"),
                    reason(.deferredCocoaPodsSemantic, "/unsupportedFields/5"),
                    reason(.deferredCocoaPodsSemantic, "/unsupportedFields/6"),
                    reason(.deferredCocoaPodsSemantic, "/unsupportedFields/7"),
                    reason(.deferredCocoaPodsSemantic, "/unsupportedFields/8"),
                    reason(.platformScopeSemanticsIndeterminate, "/ios"),
                    reason(.platformScopeSemanticsIndeterminate, "/osx"),
                    reason(
                        .platformScopeSemanticsIndeterminate,
                        "/subspecs/0/ios"
                    ),
                    reason(.platformScopeSemanticsIndeterminate, "/tvos"),
                    reason(.platformScopeSemanticsIndeterminate, "/visionos"),
                    reason(.platformScopeSemanticsIndeterminate, "/watchos"),
                    reason(.subspecSemanticsIndeterminate, "/subspecs/0"),
                    reason(.swiftVersionRequiresInspection, "/swift_version"),
                    reason(.unknownCocoaPodsSemantic, "/unsupportedFields/0"),
                    reason(.vendoredArtifactRequiresInspection, "/vendored_frameworks/0"),
                    reason(
                        .vendoredArtifactRequiresInspection,
                        "/visionos/vendored_libraries/0"
                    ),
                    reason(
                        .headerSelectionRequiresGeneratedMetadata,
                        "/osx/public_header_files"
                    ),
                    reason(
                        .headerSelectionRequiresGeneratedMetadata,
                        "/subspecs/0/ios/private_header_files"
                    ),
                    reason(
                        .linkerSettingRequiresGeneratedMetadata,
                        "/watchos/frameworks/0"
                    ),
                    reason(.resourceSelectionRequiresGeneratedMetadata, "/subspecs/0/resources"),
                    reason(.resourceSelectionRequiresGeneratedMetadata, "/tvos/resources"),
                    reason(.sourceSelectionRequiresGeneratedMetadata, "/ios/source_files"),
                ]
            ),
            FixtureExpectation(
                resourceName: "AssessmentUnsupported-5.0.0.podspec",
                sha256: "e5caf6679f41a470d5d52223c69154fc6e758bc07a1ed8ad6fcae01656f88ede",
                assessmentSHA256: "c970a56bff12c4d9b17fdc9b57d565cc27395dd20b84223eee196ff5ca54db0f",
                outcome: .unsupported,
                reasons: [
                    reason(.arcControlUnsupported, "/requires_arc"),
                    reason(.buildSettingsUnsupported, "/xcconfig/0"),
                    reason(
                        .compilerFlagsUnsupported,
                        "/subspecs/0/compiler_flags/0"
                    ),
                    reason(
                        .configurationSpecificDependencyUnsupported,
                        "/subspecs/0/configuration_pod_whitelist/0"
                    ),
                    reason(.disabledModuleMapUnsupported, "/ios/module_map"),
                    reason(.preservePathUnsupported, "/preserve_paths/0"),
                    reason(
                        .weakFrameworkLinkageUnsupported,
                        "/subspecs/0/ios/weak_frameworks/0"
                    ),
                    reason(.deferredCocoaPodsSemantic, "/unsupportedFields/0"),
                    reason(.deferredCocoaPodsSemantic, "/unsupportedFields/1"),
                    reason(.deferredCocoaPodsSemantic, "/unsupportedFields/2"),
                    reason(.platformScopeSemanticsIndeterminate, "/ios"),
                    reason(
                        .platformScopeSemanticsIndeterminate,
                        "/subspecs/0/ios"
                    ),
                    reason(.subspecSemanticsIndeterminate, "/subspecs/0"),
                    reason(
                        .dependencyRequiresGeneratedMetadata,
                        "/subspecs/0/dependencies/0"
                    ),
                ]
            ),
        ]
    }

    private func malformedModelAssessment() throws -> PodspecSwiftPMAssessment {
        let inspection = PodspecInspection(
            podspec: PodspecSemanticModel(
                version: "",
                root: PodspecNode(
                    name: "",
                    baseName: "",
                    path: "/not-a-root",
                    platforms: [],
                    declarations: .init(),
                    platformScopes: [],
                    defaultSubspecs: .implicitAll,
                    subspecs: []
                )
            ),
            unsupportedFields: []
        )
        return try assess(inspection)
    }

    private func assessFixture(named name: String) throws -> PodspecSwiftPMAssessment {
        try assess(fixtureData(named: name))
    }

    private func assess(_ data: Data) throws -> PodspecSwiftPMAssessment {
        try assess(PodspecJSONInspector().inspect(json: data))
    }

    private func assess(
        _ inspection: PodspecInspection
    ) throws -> PodspecSwiftPMAssessment {
        try PodspecSwiftPMAssessor().assess(
            inspection,
            cocoaPodsProfile: .cocoaPodsCore1_17_0,
            swiftPMProfile: .swiftToolsVersion6_0
        )
    }

    private func fixtureData(named name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/PodspecJSON"
        ))
        return try Data(contentsOf: url)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func reason(
        _ code: PodspecSwiftPMAssessmentReason.Code,
        _ path: String
    ) -> PodspecSwiftPMAssessmentReason {
        PodspecSwiftPMAssessmentReason(code: code, evidencePath: path)
    }
}

private struct FixtureExpectation: Sendable {
    let resourceName: String
    let sha256: String
    let assessmentSHA256: String
    let outcome: PodspecSwiftPMAssessment.Outcome
    let reasons: [PodspecSwiftPMAssessmentReason]
}
