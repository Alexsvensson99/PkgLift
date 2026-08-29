import CryptoKit
import Foundation
import Testing
@testable import PkgLiftCocoaPods

@Suite("Podspec Compilation Semantic Tests")
struct PodspecCompilationSemanticTests {
    @Test("Model raw compilation and file-selection controls in recursive scopes")
    func modeledRawScopes() throws {
        let fixture = try fixtureData(named: "CompilationControls-4.0.0.podspec")
        #expect(sha256(fixture) == "222d9ac7c6f92937481d16da7cd6f346a6956c6e73f8307f63837bc4c6686e01")

        let inspection = try PodspecJSONInspector().inspect(json: fixture)
        let root = inspection.podspec.root.declarations.compilation

        #expect(root.compilerFlags == [
            PodspecLiteralDeclaration(literal: "-DROOT", path: "/compiler_flags/0"),
            PodspecLiteralDeclaration(literal: "-Wno-format", path: "/compiler_flags/1"),
        ])
        #expect(root.legacyXCConfig == [
            PodspecBuildSettingDeclaration(
                key: "A/B~C",
                value: "$(inherited) -DLEGACY",
                path: "/xcconfig/A~1B~0C"
            ),
            PodspecBuildSettingDeclaration(
                key: "EMPTY_VALUE",
                value: "",
                path: "/xcconfig/EMPTY_VALUE"
            ),
        ])
        #expect(root.podTargetXCConfig == [
            PodspecBuildSettingDeclaration(
                key: "OTHER_SWIFT_FLAGS",
                value: "$(inherited) -DPOD",
                path: "/pod_target_xcconfig/OTHER_SWIFT_FLAGS"
            ),
        ])
        #expect(root.userTargetXCConfig == [
            PodspecBuildSettingDeclaration(
                key: "GCC_PREPROCESSOR_DEFINITIONS",
                value: "$(inherited) CONSUMER=1",
                path: "/user_target_xcconfig/GCC_PREPROCESSOR_DEFINITIONS"
            ),
        ])
        #expect(root.configurationPodWhitelist == [
            PodspecConfigurationPodWhitelistDeclaration(
                podName: "Logging",
                path: "/configuration_pod_whitelist/Logging",
                configurations: []
            ),
            PodspecConfigurationPodWhitelistDeclaration(
                podName: "Network/Core",
                path: "/configuration_pod_whitelist/Network~1Core",
                configurations: [
                    PodspecLiteralDeclaration(
                        literal: "debug",
                        path: "/configuration_pod_whitelist/Network~1Core/0"
                    ),
                    PodspecLiteralDeclaration(
                        literal: "release",
                        path: "/configuration_pod_whitelist/Network~1Core/1"
                    ),
                ]
            ),
        ])
        #expect(root.swiftVersions == PodspecSwiftVersionDeclarations(
            versions: [
                PodspecLiteralDeclaration(literal: "5.9", path: "/swift_versions/0"),
                PodspecLiteralDeclaration(literal: "6.0", path: "/swift_versions/1"),
            ],
            pluralDeclarationPath: "/swift_versions",
            legacySingular: PodspecLiteralDeclaration(
                literal: "6.0",
                path: "/swift_version"
            ),
            relationship: .requiresCocoaPodsNormalization
        ))
        #expect(root.requiresARC == PodspecARCDeclaration(
            value: .filePatterns([
                PodspecLiteralDeclaration(
                    literal: "Sources/**/*ARC.m",
                    path: "/requires_arc/0"
                ),
                PodspecLiteralDeclaration(
                    literal: "Sources/ARC.mm",
                    path: "/requires_arc/1"
                ),
            ]),
            path: "/requires_arc"
        ))
        #expect(root.excludeFiles.map(\.literal) == [
            "Sources/Excluded/**",
            "../Outside.m",
        ])
        #expect(root.preservePaths == [
            PodspecLiteralDeclaration(
                literal: "Generated/**/*.h",
                path: "/preserve_paths"
            ),
        ])

        let rootIOS = try #require(inspection.podspec.root.platformScopes.first {
            $0.platform == .iOS
        })
        let ios = rootIOS.declarations.compilation
        #expect(ios.compilerFlags == [
            PodspecLiteralDeclaration(literal: "-DIOS", path: "/ios/compiler_flags"),
        ])
        #expect(ios.legacyXCConfig == [
            PodspecBuildSettingDeclaration(
                key: "SDKROOT",
                value: "iphoneos",
                path: "/ios/xcconfig/SDKROOT"
            ),
        ])
        #expect(ios.requiresARC == PodspecARCDeclaration(
            value: .boolean(false),
            path: "/ios/requires_arc"
        ))
        #expect(ios.excludeFiles == [
            PodspecLiteralDeclaration(
                literal: "Sources/macOS/**",
                path: "/ios/exclude_files"
            ),
        ])
        #expect(ios.preservePaths.map(\.path) == [
            "/ios/preserve_paths/0",
            "/ios/preserve_paths/1",
        ])
        #expect(ios.swiftVersions == .empty)
        #expect(ios.configurationPodWhitelist.isEmpty)

        let core = try #require(inspection.podspec.root.subspecs.first)
        let coreCompilation = core.declarations.compilation
        #expect(coreCompilation.compilerFlags == [
            PodspecLiteralDeclaration(
                literal: "-DCORE",
                path: "/subspecs/0/compiler_flags"
            ),
        ])
        #expect(coreCompilation.configurationPodWhitelist == [
            PodspecConfigurationPodWhitelistDeclaration(
                podName: "Child/Thing",
                path: "/subspecs/0/configuration_pod_whitelist/Child~1Thing",
                configurations: [
                    PodspecLiteralDeclaration(
                        literal: "debug",
                        path: "/subspecs/0/configuration_pod_whitelist/Child~1Thing/0"
                    ),
                ]
            ),
        ])
        #expect(coreCompilation.requiresARC == PodspecARCDeclaration(
            value: .boolean(true),
            path: "/subspecs/0/requires_arc"
        ))
        #expect(coreCompilation.excludeFiles.isEmpty)

        let coreIOS = try #require(core.platformScopes.first { $0.platform == .iOS })
        let coreIOSCompilation = coreIOS.declarations.compilation
        #expect(coreIOSCompilation.podTargetXCConfig == [
            PodspecBuildSettingDeclaration(
                key: "CORE_IOS",
                value: "$(SRCROOT)/literal-only",
                path: "/subspecs/0/ios/pod_target_xcconfig/CORE_IOS"
            ),
        ])
        #expect(coreIOSCompilation.requiresARC == PodspecARCDeclaration(
            value: .filePatterns([
                PodspecLiteralDeclaration(
                    literal: "Sources/Core/iOS/*ARC.m",
                    path: "/subspecs/0/ios/requires_arc"
                ),
            ]),
            path: "/subspecs/0/ios/requires_arc"
        ))

        #expect(inspection.unsupportedFields == [
            PodspecUnsupportedField(path: "/ios", kind: .deferredCocoaPodsSemantic),
            PodspecUnsupportedField(
                path: "/ios/script_phase",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/prepare_command",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(path: "/subspecs/0", kind: .deferredCocoaPodsSemantic),
            PodspecUnsupportedField(
                path: "/subspecs/0/ios",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/subspecs/0/ios/computed~1override~0",
                kind: .unknownField
            ),
            PodspecUnsupportedField(
                path: "/swift_version",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/swift_versions",
                kind: .deferredCocoaPodsSemantic
            ),
        ])
    }

    @Test("Keep supported Swift-version forms literal and fail closed on unresolved pairs")
    func swiftVersionFormsAndUnresolvedPairs() throws {
        let singular = try inspect(#"{"name":"Example","version":"1","swift_version":"5.10"}"#)
        #expect(singular.podspec.root.declarations.compilation.swiftVersions ==
            PodspecSwiftVersionDeclarations(
                legacySingular: PodspecLiteralDeclaration(
                    literal: "5.10",
                    path: "/swift_version"
                )
            ))

        let pluralScalar = try inspect(
            #"{"name":"Example","version":"1","swift_versions":"6"}"#
        )
        #expect(pluralScalar.podspec.root.declarations.compilation.swiftVersions ==
            PodspecSwiftVersionDeclarations(
                versions: [
                    PodspecLiteralDeclaration(literal: "6", path: "/swift_versions"),
                ],
                pluralDeclarationPath: "/swift_versions"
            ))

        let explicitEmpty = try inspect(
            #"{"name":"Example","version":"1","swift_versions":[]}"#
        )
        #expect(explicitEmpty.podspec.root.declarations.compilation.swiftVersions ==
            PodspecSwiftVersionDeclarations(pluralDeclarationPath: "/swift_versions"))

        let exactSingleVersionPair = try inspect(#"""
        {
          "name": "Example",
          "version": "1",
          "swift_versions": ["6.0"],
          "swift_version": "6.0"
        }
        """#)
        #expect(exactSingleVersionPair.podspec.root.declarations.compilation
            .swiftVersions.relationship == .exactMatch)
        #expect(exactSingleVersionPair.unsupportedFields.isEmpty)

        let normalizedMultiVersionPair = try inspect(#"""
        {
          "name": "Example",
          "version": "1",
          "swift_versions": ["6.0", "5.9"],
          "swift_version": "6.0"
        }
        """#)
        #expect(normalizedMultiVersionPair.podspec.root.declarations.compilation
            .swiftVersions.legacySingular?.literal == "6.0")
        #expect(normalizedMultiVersionPair.podspec.root.declarations.compilation
            .swiftVersions.relationship == .requiresCocoaPodsNormalization)
        #expect(normalizedMultiVersionPair.unsupportedFields.map(\.path) == [
            "/swift_version",
            "/swift_versions",
        ])

        let staleOrderPair = try inspect(#"""
        {
          "name": "Example",
          "version": "1",
          "swift_versions": ["5.9", "6.0"],
          "swift_version": "5.9"
        }
        """#)
        #expect(staleOrderPair.podspec.root.declarations.compilation
            .swiftVersions.relationship == .requiresCocoaPodsNormalization)
        #expect(staleOrderPair.unsupportedFields.map(\.path) == [
            "/swift_version",
            "/swift_versions",
        ])

        let unresolved = try inspect(#"""
        {
          "name": "Example",
          "version": "1",
          "swift_versions": ["5.9", "6.0"],
          "swift_version": "5.8"
        }
        """#)
        #expect(unresolved.podspec.root.declarations.compilation.swiftVersions
            .relationship == .requiresCocoaPodsNormalization)
        #expect(unresolved.unsupportedFields == [
            PodspecUnsupportedField(
                path: "/swift_version",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/swift_versions",
                kind: .deferredCocoaPodsSemantic
            ),
        ])

        let emptyPluralPair = try inspect(#"""
        {
          "name": "Example",
          "version": "1",
          "swift_versions": [],
          "swift_version": "6.0"
        }
        """#)
        #expect(emptyPluralPair.podspec.root.declarations.compilation.swiftVersions
            .relationship == .requiresCocoaPodsNormalization)
        #expect(emptyPluralPair.unsupportedFields.map(\.path) == [
            "/swift_version",
            "/swift_versions",
        ])

        let normalizedEquivalentPair = try inspect(#"""
        {
          "name": "Example",
          "version": "1",
          "swift_versions": ["5.0"],
          "swift_version": "5"
        }
        """#)
        #expect(normalizedEquivalentPair.podspec.root.declarations.compilation
            .swiftVersions.relationship == .requiresCocoaPodsNormalization)
        #expect(normalizedEquivalentPair.unsupportedFields.map(\.path) == [
            "/swift_version",
            "/swift_versions",
        ])
    }

    @Test("Reject compilation controls outside their CocoaPods Core scopes")
    func invalidDeclarationScopes() {
        let cases: [(json: String, path: String, expected: String)] = [
            (
                #"{"name":"Example","version":"1","ios":{"swift_version":"6"}}"#,
                "/ios/swift_version",
                "absent because swift_version is a root-only, non-platform declaration"
            ),
            (
                #"{"name":"Example","version":"1","subspecs":[{"name":"Core","swift_versions":["6"]}]}"#,
                "/subspecs/0/swift_versions",
                "absent because swift_versions is a root-only, non-platform declaration"
            ),
            (
                #"{"name":"Example","version":"1","subspecs":[{"name":"Core","ios":{"swift_version":"6"}}]}"#,
                "/subspecs/0/ios/swift_version",
                "absent because swift_version is a root-only, non-platform declaration"
            ),
            (
                #"{"name":"Example","version":"1","ios":{"configuration_pod_whitelist":{}}}"#,
                "/ios/configuration_pod_whitelist",
                "absent because configuration_pod_whitelist is not a platform declaration"
            ),
        ]

        for invalidCase in cases {
            #expect(error(for: invalidCase.json) == .invalidValue(
                path: invalidCase.path,
                expected: invalidCase.expected
            ))
        }
    }

    @Test("Reject malformed compilation and file-selection values at exact paths")
    func malformedValues() {
        let cases: [(fragment: String, path: String, expected: String)] = [
            (
                #""compiler_flags": {}"#,
                "/compiler_flags",
                "a non-empty string or an array of non-empty strings"
            ),
            (
                #""compiler_flags": ["-DOK", 1]"#,
                "/compiler_flags/1",
                "a non-empty string"
            ),
            (
                #""xcconfig": []"#,
                "/xcconfig",
                "an object of string build-setting values"
            ),
            (
                #""pod_target_xcconfig": {"FLAG": true}"#,
                "/pod_target_xcconfig/FLAG",
                "a string build-setting value"
            ),
            (
                #""user_target_xcconfig": {"": "VALUE"}"#,
                "/user_target_xcconfig/",
                "a non-empty build-setting key"
            ),
            (
                #""configuration_pod_whitelist": []"#,
                "/configuration_pod_whitelist",
                "an object mapping dependency names to configuration arrays"
            ),
            (
                #""dependencies": {"Other": []}, "configuration_pod_whitelist": {"Missing": ["debug"]}"#,
                "/configuration_pod_whitelist/Missing",
                "a key matching a dependency declared in the same scope"
            ),
            (
                #""dependencies": {"Other": []}, "configuration_pod_whitelist": {"Other": "debug"}"#,
                "/configuration_pod_whitelist/Other",
                "an array containing only debug and release strings"
            ),
            (
                #""dependencies": {"Other": []}, "configuration_pod_whitelist": {"Other": ["Debug"]}"#,
                "/configuration_pod_whitelist/Other/0",
                "the literal string debug or release"
            ),
            (
                #""swift_version": []"#,
                "/swift_version",
                "a non-empty string"
            ),
            (
                #""swift_versions": ["5.9", false]"#,
                "/swift_versions/1",
                "a non-empty string"
            ),
            (
                #""requires_arc": 1"#,
                "/requires_arc",
                "a boolean, a non-empty string, or an array of non-empty strings"
            ),
            (
                #""requires_arc": ["Sources/A.m", " "]"#,
                "/requires_arc/1",
                "a non-empty string"
            ),
            (
                #""exclude_files": null"#,
                "/exclude_files",
                "a non-empty string or an array of non-empty strings"
            ),
            (
                #""preserve_paths": {"path": "A"}"#,
                "/preserve_paths",
                "a non-empty string or an array of non-empty strings"
            ),
        ]

        for invalidCase in cases {
            let json = "{\"name\":\"Example\",\"version\":\"1\",\(invalidCase.fragment)}"
            #expect(error(for: json) == .invalidValue(
                path: invalidCase.path,
                expected: invalidCase.expected
            ))
        }
    }

    @Test("Keep maps deterministic, macros opaque, and Codable backward compatible")
    func deterministicAndBackwardCodable() throws {
        let first = try inspect(#"""
        {
          "name": "Example",
          "version": "1",
          "dependencies": {"Z/Pod": [], "A~Pod": []},
          "configuration_pod_whitelist": {
            "Z/Pod": ["release"],
            "A~Pod": ["debug"]
          },
          "pod_target_xcconfig": {
            "Z/FLAG": "$(inherited)",
            "A~FLAG": "$(SRCROOT)/not-expanded"
          },
          "compiler_flags": ["-DVALUE=$(VALUE)"]
        }
        """#)
        let second = try inspect(#"""
        {
          "compiler_flags": ["-DVALUE=$(VALUE)"],
          "pod_target_xcconfig": {
            "A~FLAG": "$(SRCROOT)/not-expanded",
            "Z/FLAG": "$(inherited)"
          },
          "configuration_pod_whitelist": {
            "A~Pod": ["debug"],
            "Z/Pod": ["release"]
          },
          "dependencies": {"A~Pod": [], "Z/Pod": []},
          "version": "1",
          "name": "Example"
        }
        """#)
        #expect(first == second)
        #expect(first.podspec.root.declarations.compilation.podTargetXCConfig.map(\.path) == [
            "/pod_target_xcconfig/A~0FLAG",
            "/pod_target_xcconfig/Z~1FLAG",
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let firstBytes = try encoder.encode(first)
        let secondBytes = try encoder.encode(second)
        #expect(firstBytes == secondBytes)
        #expect(try JSONDecoder().decode(PodspecInspection.self, from: firstBytes) == first)

        let earlierShape = Data(#"""
        {
          "sourceFiles": [],
          "publicHeaders": [],
          "privateHeaders": [],
          "resources": [],
          "resourceBundles": [],
          "dependencies": [],
          "linkage": {
            "frameworks": [],
            "weakFrameworks": [],
            "libraries": [],
            "vendoredFrameworks": [],
            "vendoredLibraries": [],
            "moduleName": null,
            "moduleMap": null,
            "headerDirectory": null,
            "headerMappingsDirectory": null,
            "projectHeaders": [],
            "staticFramework": null
          }
        }
        """#.utf8)
        let decoded = try JSONDecoder().decode(PodspecScopedDeclarations.self, from: earlierShape)
        #expect(decoded.compilation == .empty)
    }

    @Test("Treat duplicate compilation keys as typed JSON conflicts")
    func duplicateCompilationKey() {
        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1",
          "requires_arc": true,
          "requires_arc": false
        }
        """#) == .duplicateObjectKey(path: "/requires_arc"))
    }

    private func inspect(_ json: String) throws -> PodspecInspection {
        try PodspecJSONInspector().inspect(json: Data(json.utf8))
    }

    private func error(for json: String) -> PodspecInspectionError? {
        do {
            _ = try inspect(json)
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
