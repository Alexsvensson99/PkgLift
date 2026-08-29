import Foundation
import Testing
@testable import PkgLiftCocoaPods

@Suite("Podspec SwiftPM Assessment Tests")
struct PodspecSwiftPMAssessmentTests {
    @Test("Return declaration-compatible only for a fully covered empty declaration surface")
    func declarationCompatible() throws {
        let result = try assess(#"{"name":"Example","version":"1.0"}"#)

        #expect(result.schemaVersion == 1)
        #expect(result.cocoaPodsProfile == .cocoaPodsCore1_17_0)
        #expect(result.swiftPMProfile == .swiftToolsVersion6_0)
        #expect(result.outcome == .declarationCompatible)
        #expect(result.reasons.isEmpty)
    }

    @Test("Identify known declaration categories that require generated metadata")
    func requiresGeneratedMetadata() throws {
        let result = try assess(#"""
        {
          "name": "Example",
          "version": "1.0",
          "platforms": {"ios": "15.0"},
          "source_files": ["Sources/**/*.swift"],
          "resources": ["Resources/private-token.png"],
          "frameworks": ["Security"],
          "exclude_files": ["Sources/Generated.swift"]
        }
        """#)

        #expect(result.outcome == .requiresGeneratedMetadata)
        #expect(Set(result.reasons) == Set([
            reason(.platformRequiresGeneratedMetadata, "/platforms/ios"),
            reason(.sourceSelectionRequiresGeneratedMetadata, "/source_files"),
            reason(.resourceSelectionRequiresGeneratedMetadata, "/resources"),
            reason(.linkerSettingRequiresGeneratedMetadata, "/frameworks/0"),
            reason(.fileExclusionRequiresGeneratedMetadata, "/exclude_files/0"),
        ]))
    }

    @Test("Keep opaque and deferred evidence indeterminate")
    func indeterminate() throws {
        let result = try assess(#"""
        {
          "name": "Example",
          "version": "1.0",
          "source": {"http": "https://token@example.invalid/private.git"},
          "vendored_frameworks": ["/Users/private/Secret.xcframework"]
        }
        """#)

        #expect(result.outcome == .indeterminate)
        #expect(result.reasons == [
            reason(.deferredCocoaPodsSemantic, "/unsupportedFields/0"),
            reason(.vendoredArtifactRequiresInspection, "/vendored_frameworks/0"),
        ])
    }

    @Test("Give unsupported evidence precedence without dropping weaker reasons")
    func unsupportedReasonPrecedence() throws {
        let result = try assess(#"""
        {
          "name": "Example",
          "version": "1.0",
          "source_files": ["Sources/**/*.swift"],
          "prepare_command": "printf secret",
          "compiler_flags": ["-DPRIVATE_TOKEN=secret"],
          "weak_frameworks": ["WeakKit"]
        }
        """#)

        #expect(result.outcome == .unsupported)
        #expect(result.reasons.map(\.code) == [
            .compilerFlagsUnsupported,
            .weakFrameworkLinkageUnsupported,
            .deferredCocoaPodsSemantic,
            .sourceSelectionRequiresGeneratedMetadata,
        ])
        #expect(result.reasons.map(\.evidencePath) == [
            "/compiler_flags/0",
            "/weak_frameworks/0",
            "/unsupportedFields/0",
            "/source_files",
        ])
    }

    @Test("Reject unknown or mismatched profiles with typed errors")
    func profileValidation() throws {
        let inspection = try inspect(#"{"name":"Example","version":"1.0"}"#)
        let unknownCocoaPods = CocoaPodsSemanticProfile(
            identifier: "cocoapods-core/9.9.9"
        )
        let unknownSwiftPM = SwiftPMCapabilityProfile(
            identifier: "swift-tools-version/99.0"
        )

        #expect(throws: PodspecSwiftPMAssessmentError.unsupportedCocoaPodsSemanticProfile(
            identifier: "cocoapods-core/9.9.9"
        )) {
            try PodspecSwiftPMAssessor().assess(
                inspection,
                cocoaPodsProfile: unknownCocoaPods,
                swiftPMProfile: .swiftToolsVersion6_0
            )
        }
        #expect(throws: PodspecSwiftPMAssessmentError.unsupportedSwiftPMCapabilityProfile(
            identifier: "swift-tools-version/99.0"
        )) {
            try PodspecSwiftPMAssessor().assess(
                inspection,
                cocoaPodsProfile: .cocoaPodsCore1_17_0,
                swiftPMProfile: unknownSwiftPM
            )
        }

        let mismatched = PodspecInspection(
            podspec: PodspecSemanticModel(
                semanticProfile: unknownCocoaPods,
                version: inspection.podspec.version,
                root: inspection.podspec.root
            ),
            unsupportedFields: inspection.unsupportedFields
        )
        #expect(throws: PodspecSwiftPMAssessmentError.cocoaPodsSemanticProfileMismatch(
            requested: "cocoapods-core/1.17.0",
            inspected: "cocoapods-core/9.9.9"
        )) {
            try PodspecSwiftPMAssessor().assess(
                mismatched,
                cocoaPodsProfile: .cocoaPodsCore1_17_0,
                swiftPMProfile: .swiftToolsVersion6_0
            )
        }
    }

    @Test("Keep assessment bytes deterministic, round-trippable, and schema explicit")
    func deterministicCodableSnapshot() throws {
        let first = try assess(#"""
        {
          "name": "Example",
          "version": "1.0",
          "dependencies": {"Zulu": [], "Alpha": ["~> 1"]},
          "resource_bundles": {"Images": ["Images/*.png"]}
        }
        """#)
        let second = try assess(#"""
        {
          "resource_bundles": {"Images": ["Images/*.png"]},
          "dependencies": {"Alpha": ["~> 1"], "Zulu": []},
          "version": "1.0",
          "name": "Example"
        }
        """#)

        #expect(first == second)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let firstBytes = try encoder.encode(first)
        let secondBytes = try encoder.encode(second)
        #expect(firstBytes == secondBytes)
        #expect(try JSONDecoder().decode(
            PodspecSwiftPMAssessment.self,
            from: firstBytes
        ) == first)
        #expect(String(decoding: firstBytes, as: UTF8.self) == #"{"cocoaPodsProfile":"cocoapods-core/1.17.0","outcome":"requiresGeneratedMetadata","reasons":[{"code":"dependencyRequiresGeneratedMetadata","evidencePath":"/dependencies/0"},{"code":"dependencyRequiresGeneratedMetadata","evidencePath":"/dependencies/1"},{"code":"resourceBundleRequiresGeneratedMetadata","evidencePath":"/resource_bundles"}],"schemaVersion":1,"swiftPMProfile":"swift-tools-version/6.0"}"#)
    }

    @Test("Exclude raw secrets and local paths from assessment artifacts")
    func privacyBoundary() throws {
        let result = try assess(#"""
        {
          "name": "Example",
          "version": "1.0",
          "source": {"git": "https://private-token@example.invalid/repo.git"},
          "compiler_flags": ["-DAPI_SECRET=super-secret"],
          "vendored_frameworks": ["/Users/alex/private/Secret.xcframework"],
          "dependencies": {"dependency-secret-123": []},
          "xcconfig": {"SETTING_SECRET_KEY": "setting-secret-value"},
          "configuration_pod_whitelist": {"dependency-secret-123": ["debug"]},
          "api-secret-super-secret": true,
          "local-/Users/alex/private": true
        }
        """#)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = String(decoding: try encoder.encode(result), as: UTF8.self)

        #expect(!encoded.contains("private-token"))
        #expect(!encoded.contains("super-secret"))
        #expect(!encoded.contains("/Users/alex"))
        #expect(!encoded.contains("dependency-secret-123"))
        #expect(!encoded.contains("SETTING_SECRET_KEY"))
        #expect(!encoded.contains("setting-secret-value"))
        #expect(encoded.contains(#""evidencePath":"/unsupportedFields/0""#))
        #expect(encoded.contains(#""evidencePath":"/unsupportedFields/1""#))
        #expect(encoded.contains(#""evidencePath":"/unsupportedFields/2""#))
        #expect(encoded.contains(#""evidencePath":"/compiler_flags/0""#))
        #expect(encoded.contains(#""evidencePath":"/dependencies/0""#))
        #expect(encoded.contains(#""evidencePath":"/xcconfig/0""#))
        #expect(encoded.contains(
            #""evidencePath":"/configuration_pod_whitelist/0""#
        ))
        #expect(encoded.contains(#""evidencePath":"/vendored_frameworks/0""#))
    }

    @Test("Make every added negative evidence step monotonic")
    func monotonicDowngrades() throws {
        let compatible = try assess(#"{"name":"Example","version":"1"}"#)
        let generated = try assess(#"""
        {"name":"Example","version":"1","source_files":["Sources/*.swift"]}
        """#)
        let indeterminate = try assess(#"""
        {
          "name":"Example",
          "version":"1",
          "source_files":["Sources/*.swift"],
          "future_semantic": true
        }
        """#)
        let unsupported = try assess(#"""
        {
          "name":"Example",
          "version":"1",
          "source_files":["Sources/*.swift"],
          "future_semantic": true,
          "compiler_flags":["-DVALUE"]
        }
        """#)

        #expect(compatible.outcome == .declarationCompatible)
        #expect(generated.outcome == .requiresGeneratedMetadata)
        #expect(indeterminate.outcome == .indeterminate)
        #expect(unsupported.outcome == .unsupported)
        #expect(unsupported.reasons.contains(
            reason(.unknownCocoaPodsSemantic, "/unsupportedFields/0")
        ))
    }

    @Test("Downgrade malformed public model evidence without echoing it")
    func malformedModeledEvidence() throws {
        let malformedModel = PodspecSemanticModel(
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
        )
        let inspection = PodspecInspection(
            podspec: malformedModel,
            unsupportedFields: [
                PodspecUnsupportedField(path: "/invalid~2pointer", kind: .unknownField),
            ]
        )

        let result = try PodspecSwiftPMAssessor().assess(
            inspection,
            cocoaPodsProfile: .cocoaPodsCore1_17_0,
            swiftPMProfile: .swiftToolsVersion6_0
        )

        #expect(result.outcome == .indeterminate)
        #expect(result.reasons == [reason(.incompleteModeledSemantic, "")])
        #expect(!result.reasons.description.contains("invalid~2pointer"))
    }

    @Test("Downgrade contradictory defaults, relationships, and raw scopes")
    func contradictoryPublicModels() throws {
        let malformedDefaults = PodspecDefaultSubspecSelection(
            kind: .named,
            declarationPath: nil,
            valuePath: nil,
            references: []
        )
        let defaultInspection = PodspecInspection(
            podspec: PodspecSemanticModel(
                version: "1",
                root: PodspecNode(
                    name: "Example",
                    baseName: "Example",
                    path: "",
                    platforms: [],
                    declarations: .init(),
                    platformScopes: [],
                    defaultSubspecs: malformedDefaults,
                    subspecs: []
                )
            ),
            unsupportedFields: []
        )
        let defaultResult = try assess(defaultInspection)
        #expect(defaultResult.outcome == .indeterminate)
        #expect(defaultResult.reasons == [
            reason(.incompleteModeledSemantic, "/default_subspecs"),
        ])

        let invalidIdentityInspection = PodspecInspection(
            podspec: PodspecSemanticModel(
                version: "1",
                root: PodspecNode(
                    name: "Bad/Name",
                    baseName: "Bad/Name",
                    path: "",
                    platforms: [],
                    declarations: .init(),
                    platformScopes: [],
                    defaultSubspecs: .implicitAll,
                    subspecs: []
                )
            ),
            unsupportedFields: []
        )
        let invalidIdentityResult = try assess(invalidIdentityInspection)
        #expect(invalidIdentityResult.outcome == .indeterminate)
        #expect(invalidIdentityResult.reasons == [
            reason(.incompleteModeledSemantic, ""),
        ])

        let invalidDeclarationsInspection = PodspecInspection(
            podspec: PodspecSemanticModel(
                version: "1",
                root: PodspecNode(
                    name: "Example",
                    baseName: "Example",
                    path: "",
                    platforms: [
                        PodspecPlatformRequirement(platform: .iOS, minimumVersion: ""),
                    ],
                    declarations: PodspecScopedDeclarations(sourceFiles: [""]),
                    platformScopes: [],
                    defaultSubspecs: .implicitAll,
                    subspecs: []
                )
            ),
            unsupportedFields: []
        )
        let invalidDeclarationsResult = try assess(invalidDeclarationsInspection)
        #expect(invalidDeclarationsResult.outcome == .indeterminate)
        #expect(invalidDeclarationsResult.reasons.contains(
            reason(.incompleteModeledSemantic, "/platforms")
        ))
        #expect(invalidDeclarationsResult.reasons.contains(
            reason(.incompleteModeledSemantic, "/source_files/0")
        ))

        let impossibleDefaultInspection = PodspecInspection(
            podspec: PodspecSemanticModel(
                version: "1",
                root: PodspecNode(
                    name: "Example",
                    baseName: "Example",
                    path: "",
                    platforms: [],
                    declarations: .init(),
                    platformScopes: [],
                    defaultSubspecs: PodspecDefaultSubspecSelection(
                        kind: .all,
                        declarationPath: "/default_subspec",
                        valuePath: "/default_subspec",
                        references: []
                    ),
                    subspecs: []
                )
            ),
            unsupportedFields: []
        )
        let impossibleDefaultResult = try assess(impossibleDefaultInspection)
        #expect(impossibleDefaultResult.outcome == .indeterminate)
        #expect(impossibleDefaultResult.reasons == [
            reason(.incompleteModeledSemantic, "/default_subspec"),
        ])

        let invalidPathInspection = PodspecInspection(
            podspec: PodspecSemanticModel(
                version: "1",
                root: PodspecNode(
                    name: "Example",
                    baseName: "Example",
                    path: "",
                    platforms: [],
                    declarations: PodspecScopedDeclarations(
                        dependencies: [
                            PodspecDependencyDeclaration(
                                name: "Dependency",
                                path: "/Users/private/dependency-secret",
                                requirements: []
                            ),
                        ]
                    ),
                    platformScopes: [],
                    defaultSubspecs: .implicitAll,
                    subspecs: []
                )
            ),
            unsupportedFields: []
        )
        let invalidPathResult = try assess(invalidPathInspection)
        #expect(invalidPathResult.outcome == .indeterminate)
        #expect(invalidPathResult.reasons.contains(
            reason(.incompleteModeledSemantic, "/dependencies/0")
        ))
        let invalidPathData = try JSONEncoder().encode(invalidPathResult)
        #expect(!String(decoding: invalidPathData, as: UTF8.self).contains("/Users/private"))

        let contradictoryVersions = PodspecSwiftVersionDeclarations(
            relationship: .requiresCocoaPodsNormalization
        )
        let versionInspection = PodspecInspection(
            podspec: PodspecSemanticModel(
                version: "1",
                root: PodspecNode(
                    name: "Example",
                    baseName: "Example",
                    path: "",
                    platforms: [],
                    declarations: PodspecScopedDeclarations(
                        compilation: PodspecCompilationDeclarations(
                            swiftVersions: contradictoryVersions
                        )
                    ),
                    platformScopes: [],
                    defaultSubspecs: .implicitAll,
                    subspecs: []
                )
            ),
            unsupportedFields: []
        )
        let versionResult = try assess(versionInspection)
        #expect(versionResult.outcome == .indeterminate)
        #expect(versionResult.reasons == [
            reason(.incompleteModeledSemantic, "/swift_versions"),
        ])

        let child = PodspecNode(
            name: "Example/Core",
            baseName: "Core",
            path: "/subspecs/0",
            platforms: [],
            declarations: .init(),
            platformScopes: [],
            defaultSubspecs: .implicitAll,
            subspecs: []
        )
        let recursiveInspection = PodspecInspection(
            podspec: PodspecSemanticModel(
                version: "1",
                root: PodspecNode(
                    name: "Example",
                    baseName: "Example",
                    path: "",
                    platforms: [],
                    declarations: .init(),
                    platformScopes: [],
                    defaultSubspecs: .implicitAll,
                    subspecs: [child]
                )
            ),
            unsupportedFields: []
        )
        let recursiveResult = try assess(recursiveInspection)
        #expect(recursiveResult.outcome == .indeterminate)
        #expect(recursiveResult.reasons == [
            reason(.subspecSemanticsIndeterminate, "/subspecs/0"),
        ])
    }

    @Test("Reject noncanonical assessment artifacts during decoding")
    func rejectNoncanonicalAssessmentArtifacts() {
        #expect(throws: PodspecSwiftPMAssessmentError.unsupportedAssessmentSchemaVersion(
            99
        )) {
            try decodeAssessment(#"""
            {
              "schemaVersion": 99,
              "cocoaPodsProfile": "cocoapods-core/1.17.0",
              "swiftPMProfile": "swift-tools-version/6.0",
              "outcome": "futureOutcome",
              "reasons": [{"code":"futureReason","evidencePath":"/future"}]
            }
            """#)
        }

        #expect(throws: PodspecSwiftPMAssessmentError.unsupportedCocoaPodsSemanticProfile(
            identifier: "cocoapods-core/99.0.0"
        )) {
            try decodeAssessment(#"""
            {
              "schemaVersion": 1,
              "cocoaPodsProfile": "cocoapods-core/99.0.0",
              "swiftPMProfile": "swift-tools-version/6.0",
              "outcome": "futureOutcome",
              "reasons": []
            }
            """#)
        }

        #expect(throws: PodspecSwiftPMAssessmentError.invalidAssessmentContract) {
            try decodeAssessment(#"""
            {
              "schemaVersion": 1,
              "cocoaPodsProfile": "cocoapods-core/1.17.0",
              "swiftPMProfile": "swift-tools-version/6.0",
              "outcome": "unsupported",
              "reasons": [
                {
                  "code": "sourceSelectionRequiresGeneratedMetadata",
                  "evidencePath": "/source_files"
                },
                {
                  "code": "compilerFlagsUnsupported",
                  "evidencePath": "/compiler_flags/0"
                }
              ]
            }
            """#)
        }

        #expect(throws: PodspecSwiftPMAssessmentError.unsupportedSwiftPMCapabilityProfile(
            identifier: "swift-tools-version/99.0"
        )) {
            try decodeAssessment(#"""
            {
              "schemaVersion": 1,
              "cocoaPodsProfile": "cocoapods-core/1.17.0",
              "swiftPMProfile": "swift-tools-version/99.0",
              "outcome": "futureOutcome",
              "reasons": []
            }
            """#)
        }
    }

    private func assess(_ json: String) throws -> PodspecSwiftPMAssessment {
        try assess(inspect(json))
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

    private func inspect(_ json: String) throws -> PodspecInspection {
        try PodspecJSONInspector().inspect(json: Data(json.utf8))
    }

    private func reason(
        _ code: PodspecSwiftPMAssessmentReason.Code,
        _ path: String
    ) -> PodspecSwiftPMAssessmentReason {
        PodspecSwiftPMAssessmentReason(code: code, evidencePath: path)
    }

    private func decodeAssessment(_ json: String) throws -> PodspecSwiftPMAssessment {
        try JSONDecoder().decode(
            PodspecSwiftPMAssessment.self,
            from: Data(json.utf8)
        )
    }
}
