import CryptoKit
import Foundation
import Testing
@testable import PkgLiftCocoaPods

@Suite("Recursive Podspec Semantic Tests")
struct PodspecRecursiveSemanticTests {
    @Test("Model recursive dependencies, defaults, and raw platform scopes")
    func recursiveHierarchyAndScopes() throws {
        let fixture = try fixtureData(named: "RecursiveScopes-2.0.0.podspec")
        #expect(sha256(fixture) == "76074af53185960a37304152c61c365f99460ce6545bc27920d25f851aa024d2")
        let inspection = try PodspecJSONInspector().inspect(json: fixture)

        let podspec = inspection.podspec
        #expect(podspec.semanticProfile == .cocoaPodsCore1_17_0)
        #expect(podspec.semanticProfile.identifier == "cocoapods-core/1.17.0")
        #expect(podspec.name == "Example")
        #expect(podspec.version == "2.0.0")
        #expect(podspec.root.path == "")
        #expect(podspec.root.baseName == "Example")
        #expect(podspec.root.platforms == [
            PodspecPlatformRequirement(platform: .iOS, minimumVersion: "14.0"),
            PodspecPlatformRequirement(platform: .visionOS, minimumVersion: "1.0"),
        ])

        #expect(podspec.root.declarations.dependencies.map(\.name) == [
            "Alpha/Core",
            "Zeta",
        ])
        #expect(podspec.root.declarations.dependencies[0].path == "/dependencies/Alpha~1Core")
        #expect(podspec.root.declarations.dependencies[0].requirements == [
            PodspecDependencyRequirement(
                literal: "~> 1.0",
                path: "/dependencies/Alpha~1Core/0"
            ),
            PodspecDependencyRequirement(
                literal: "< 2.0",
                path: "/dependencies/Alpha~1Core/1"
            ),
        ])
        #expect(podspec.root.declarations.dependencies[1].requirements.isEmpty)

        #expect(podspec.root.platformScopes.count == 1)
        #expect(podspec.root.platformScopes[0].platform == .iOS)
        #expect(podspec.root.platformScopes[0].path == "/ios")
        #expect(podspec.root.platformScopes[0].declarations.sourceFiles == [
            "Sources/iOS/**/*.swift",
        ])
        #expect(podspec.root.platformScopes[0].declarations.dependencies[0].path ==
            "/ios/dependencies/UIKitHelper")

        let core = try #require(podspec.root.subspecs.first)
        #expect(core.name == "Example/Core")
        #expect(core.baseName == "Core")
        #expect(core.path == "/subspecs/0")
        #expect(core.declarations.sourceFiles == ["Sources/Core/**/*.swift"])
        #expect(core.defaultSubspecs == .implicitAll)

        let networking = try #require(core.subspecs.first)
        #expect(networking.name == "Example/Core/Networking")
        #expect(networking.path == "/subspecs/0/subspecs/0")
        #expect(networking.declarations.dependencies[0].requirements[0].literal == "~> 4.1")
        #expect(networking.platformScopes[0].path == "/subspecs/0/subspecs/0/watchos")
        #expect(networking.platformScopes[0].declarations.dependencies[0].path ==
            "/subspecs/0/subspecs/0/watchos/dependencies/WatchTransport")

        #expect(podspec.root.defaultSubspecs.kind == .named)
        #expect(podspec.root.defaultSubspecs.declarationPath == "/default_subspecs")
        #expect(podspec.root.defaultSubspecs.references == [
            PodspecDefaultSubspecReference(
                name: "Core/Networking",
                resolvedName: "Example/Core/Networking",
                path: "/default_subspecs/0"
            ),
            PodspecDefaultSubspecReference(
                name: "UI",
                resolvedName: "Example/UI",
                path: "/default_subspecs/1"
            ),
        ])

        #expect(inspection.unsupportedFields == [
            PodspecUnsupportedField(
                path: "/ios",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/subspecs/0",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/subspecs/0/subspecs/0",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/subspecs/0/subspecs/0/watchos",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/subspecs/1",
                kind: .deferredCocoaPodsSemantic
            ),
        ])
    }

    @Test("Model singular, none, implicit, and explicit-empty defaults")
    func defaultForms() throws {
        let singular = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0",
          "default_subspec": "Core",
          "subspecs": [{"name": "Core"}]
        }
        """#)
        #expect(singular.podspec.root.defaultSubspecs.kind == .named)
        #expect(singular.podspec.root.defaultSubspecs.references[0].path == "/default_subspec")

        let none = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0",
          "default_subspecs": "none",
          "subspecs": [{"name": "Core"}]
        }
        """#)
        #expect(none.podspec.root.defaultSubspecs == PodspecDefaultSubspecSelection(
            kind: .none,
            declarationPath: "/default_subspecs",
            valuePath: "/default_subspecs",
            references: []
        ))

        let singletonNone = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0",
          "default_subspecs": ["none"],
          "subspecs": [{"name": "Core"}]
        }
        """#)
        #expect(singletonNone.podspec.root.defaultSubspecs.kind == .none)
        #expect(singletonNone.podspec.root.defaultSubspecs.valuePath == "/default_subspecs/0")

        let implicit = try inspect(#"{"name":"Example","version":"1.0"}"#)
        #expect(implicit.podspec.root.defaultSubspecs == .implicitAll)

        let explicitEmpty = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0",
          "default_subspecs": []
        }
        """#)
        #expect(explicitEmpty.podspec.root.defaultSubspecs == PodspecDefaultSubspecSelection(
            kind: .all,
            declarationPath: "/default_subspecs",
            valuePath: "/default_subspecs",
            references: []
        ))
    }

    @Test("Reject unknown semantic profiles before decoding input")
    func unknownProfile() {
        let inspector = PodspecJSONInspector(
            semanticProfile: CocoaPodsSemanticProfile(identifier: "cocoapods-core/9.9.9")
        )
        #expect(throws: PodspecInspectionError.unsupportedSemanticProfile(
            identifier: "cocoapods-core/9.9.9"
        )) {
            try inspector.inspect(json: Data("{".utf8))
        }
    }

    @Test("Reject duplicate sibling identities without collapsing evidence")
    func duplicateSubspecIdentity() {
        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "subspecs": [
            {"name": "Core"},
            {"name": "Core"}
          ]
        }
        """#) == .duplicateSubspecIdentity(
            name: "Example/Core",
            path: "/subspecs/1/name",
            firstPath: "/subspecs/0/name"
        ))
    }

    @Test("Reject ambiguous or unresolved default declarations")
    func invalidDefaults() {
        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "default_subspec": "Core",
          "default_subspecs": ["Core"],
          "subspecs": [{"name": "Core"}]
        }
        """#) == .conflictingDefaultSubspecDeclarations(
            firstPath: "/default_subspec",
            secondPath: "/default_subspecs"
        ))

        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "default_subspecs": ["none", "Core"],
          "subspecs": [{"name": "Core"}]
        }
        """#) == .invalidValue(
            path: "/default_subspecs/0",
            expected: "the sole default value when using the reserved none form"
        ))

        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "default_subspecs": "core",
          "subspecs": [{"name": "Core"}]
        }
        """#) == .invalidDefaultSubspecReference(
            name: "core",
            path: "/default_subspecs"
        ))

        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "default_subspecs": ["Core", "Core"],
          "subspecs": [{"name": "Core"}]
        }
        """#) == .invalidValue(
            path: "/default_subspecs/1",
            expected: "a unique default subspec reference"
        ))

        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "default_subspecs": "Group/Missing",
          "subspecs": [
            {"name": "Group", "subspecs": [{"name": "Leaf"}]}
          ]
        }
        """#) == .invalidDefaultSubspecReference(
            name: "Group/Missing",
            path: "/default_subspecs"
        ))
    }

    @Test("Reject malformed dependency and structural forms at exact paths")
    func malformedForms() {
        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "dependencies": {"Other": "~> 1.0"}
        }
        """#) == .invalidValue(
            path: "/dependencies/Other",
            expected: "an array of non-empty literal requirement strings"
        ))

        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "dependencies": {"Other": [">= 1", " "]}
        }
        """#) == .invalidValue(
            path: "/dependencies/Other/1",
            expected: "a non-empty literal requirement string"
        ))

        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "subspecs": [{"name": ""}]
        }
        """#) == .invalidValue(
            path: "/subspecs/0/name",
            expected: "a non-empty string"
        ))

        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "ios": []
        }
        """#) == .invalidValue(path: "/ios", expected: "an object"))

        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "subspecs": [42]
        }
        """#) == .invalidValue(
            path: "/subspecs/0",
            expected: "a subspec object"
        ))

        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "ios": {"default_subspecs": "none"}
        }
        """#) == .invalidValue(
            path: "/ios/default_subspecs",
            expected: "absent because defaults are root-only declarations"
        ))
    }

    @Test("Classify nested deferred and unknown fields with escaped pointers")
    func nestedUnsupportedFields() throws {
        let inspection = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0",
          "subspecs": [
            {
              "name": "Core",
              "summary": "Descriptive metadata",
              "frameworks": "Foundation",
              "custom/field~": true,
              "ios": {
                "compiler_flags": "-DVALUE",
                "homepage": "https://invalid.example",
                "project_header_files": "Headers/Project/*.h",
                "unknown/nested~": true
              }
            }
          ]
        }
        """#)

        #expect(inspection.unsupportedFields == [
            PodspecUnsupportedField(
                path: "/subspecs/0",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/subspecs/0/custom~1field~0",
                kind: .unknownField
            ),
            PodspecUnsupportedField(
                path: "/subspecs/0/frameworks",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/subspecs/0/ios",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/subspecs/0/ios/compiler_flags",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/subspecs/0/ios/homepage",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/subspecs/0/ios/project_header_files",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/subspecs/0/ios/unknown~1nested~0",
                kind: .unknownField
            ),
            PodspecUnsupportedField(
                path: "/subspecs/0/summary",
                kind: .deferredCocoaPodsSemantic
            ),
        ])
    }

    @Test("Keep deterministic model and sorted-key Codable bytes")
    func deterministicCodable() throws {
        let first = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0",
          "dependencies": {"Z": [], "A": ["~> 1"]},
          "resource_bundles": {"Z": "Z.png", "A": "A.png"}
        }
        """#)
        let second = try inspect(#"""
        {
          "resource_bundles": {"A": "A.png", "Z": "Z.png"},
          "dependencies": {"A": ["~> 1"], "Z": []},
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
        #expect(String(decoding: firstBytes, as: UTF8.self).contains(
            #""semanticProfile":"cocoapods-core/1.17.0""#
        ))
    }

    @Test("Existing JSON depth limits bound recursive subspec input")
    func recursiveLimitBoundary() {
        #expect(error(
            for: #"""
            {
              "name": "Example",
              "version": "1.0",
              "subspecs": [{"name": "Core"}]
            }
            """#,
            limits: PodspecInspectionLimits(maximumNestingDepth: 2)
        ) == .limitExceeded(
            path: "/subspecs/0/name",
            actual: 3,
            maximum: 2
        ))
    }

    @Test("Preserve the original flat initializer as a root projection")
    func flatCompatibilityInitializer() {
        let model = PodspecSemanticModel(
            name: "Example",
            version: "1.0",
            platforms: [.init(platform: .iOS, minimumVersion: "13.0")],
            sourceFiles: ["Sources/**/*.swift"],
            publicHeaders: [],
            privateHeaders: [],
            resources: [],
            resourceBundles: []
        )
        #expect(model.semanticProfile == .cocoaPodsCore1_17_0)
        #expect(model.root.name == "Example")
        #expect(model.sourceFiles == ["Sources/**/*.swift"])
    }

    private func inspect(_ json: String) throws -> PodspecInspection {
        try PodspecJSONInspector().inspect(json: Data(json.utf8))
    }

    private func error(
        for json: String,
        limits: PodspecInspectionLimits = .default
    ) -> PodspecInspectionError? {
        do {
            _ = try PodspecJSONInspector(limits: limits).inspect(json: Data(json.utf8))
            return nil
        } catch let error as PodspecInspectionError {
            return error
        } catch {
            Issue.record("Unexpected error type: \(error)")
            return nil
        }
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
}
