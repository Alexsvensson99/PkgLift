import CryptoKit
import Foundation
import Testing
@testable import PkgLiftCocoaPods

@Suite("Podspec Linkage Semantic Tests")
struct PodspecLinkageSemanticTests {
    @Test("Model linkage, module, header, and vendored declarations in raw scopes")
    func modeledRawScopes() throws {
        let fixture = try fixtureData(named: "LinkageModules-3.0.0.podspec")
        #expect(sha256(fixture) == "70de6cdf72b353dd88cfc7a8913fd55830fb22686285b110b67c2843c75a41b5")

        let inspection = try PodspecJSONInspector().inspect(json: fixture)
        let root = inspection.podspec.root.declarations.linkage

        #expect(root.frameworks == [
            PodspecLiteralDeclaration(literal: "Foundation", path: "/frameworks/0"),
            PodspecLiteralDeclaration(literal: "CoreGraphics", path: "/frameworks/1"),
        ])
        #expect(root.weakFrameworks == [
            PodspecLiteralDeclaration(literal: "Metal", path: "/weak_frameworks"),
        ])
        #expect(root.libraries == [
            PodspecLiteralDeclaration(literal: "z", path: "/libraries/0"),
            PodspecLiteralDeclaration(literal: "sqlite3", path: "/libraries/1"),
        ])
        #expect(root.vendoredFrameworks == [
            PodspecLiteralDeclaration(
                literal: "Artifacts/Foo.framework",
                path: "/vendored_frameworks/0"
            ),
            PodspecLiteralDeclaration(
                literal: "Artifacts/Foo.xcframework",
                path: "/vendored_frameworks/1"
            ),
        ])
        #expect(root.vendoredLibraries == [
            PodspecLiteralDeclaration(
                literal: "Artifacts/libFoo.a",
                path: "/vendored_libraries/0"
            ),
            PodspecLiteralDeclaration(
                literal: "Artifacts/libBar.dylib",
                path: "/vendored_libraries/1"
            ),
        ])
        #expect(root.moduleName == PodspecLiteralDeclaration(
            literal: "BinaryKitCore",
            path: "/module_name"
        ))
        #expect(root.moduleMap == PodspecModuleMapDeclaration(
            value: .customPath("Modules/module.modulemap"),
            path: "/module_map"
        ))
        #expect(root.headerDirectory == PodspecLiteralDeclaration(
            literal: "BinaryKit",
            path: "/header_dir"
        ))
        #expect(root.headerMappingsDirectory == PodspecLiteralDeclaration(
            literal: "Sources/include",
            path: "/header_mappings_dir"
        ))
        #expect(root.projectHeaders == [
            PodspecLiteralDeclaration(
                literal: "Sources/Project/*.h",
                path: "/project_header_files/0"
            ),
            PodspecLiteralDeclaration(
                literal: "Sources/Project/Generated.h",
                path: "/project_header_files/1"
            ),
        ])
        #expect(root.staticFramework == PodspecBooleanDeclaration(
            value: false,
            path: "/static_framework"
        ))

        let rootIOS = try #require(inspection.podspec.root.platformScopes.first {
            $0.platform == .iOS
        })
        #expect(rootIOS.declarations.linkage.frameworks == [
            PodspecLiteralDeclaration(literal: "UIKit", path: "/ios/frameworks"),
        ])
        #expect(rootIOS.declarations.linkage.moduleMap == PodspecModuleMapDeclaration(
            value: .disabled,
            path: "/ios/module_map"
        ))
        #expect(rootIOS.declarations.linkage.vendoredFrameworks == [
            PodspecLiteralDeclaration(
                literal: "Artifacts/iOS/Feature.xcframework",
                path: "/ios/vendored_frameworks"
            ),
        ])
        #expect(rootIOS.declarations.linkage.headerDirectory == PodspecLiteralDeclaration(
            literal: "BinaryKit/iOS",
            path: "/ios/header_dir"
        ))

        let extras = try #require(inspection.podspec.root.subspecs.first)
        #expect(extras.declarations.linkage.frameworks == [
            PodspecLiteralDeclaration(
                literal: "AVFoundation",
                path: "/subspecs/0/frameworks"
            ),
        ])
        #expect(extras.declarations.linkage.vendoredLibraries == [
            PodspecLiteralDeclaration(
                literal: "Artifacts/Extras/libExtras.a",
                path: "/subspecs/0/vendored_libraries"
            ),
        ])
        #expect(extras.declarations.linkage.moduleName == nil)
        #expect(extras.declarations.linkage.moduleMap == nil)
        #expect(extras.declarations.linkage.staticFramework == nil)

        let extrasIOS = try #require(extras.platformScopes.first { $0.platform == .iOS })
        #expect(extrasIOS.declarations.linkage.weakFrameworks == [
            PodspecLiteralDeclaration(
                literal: "PhotosUI",
                path: "/subspecs/0/ios/weak_frameworks"
            ),
        ])
        #expect(extrasIOS.declarations.linkage.projectHeaders == [
            PodspecLiteralDeclaration(
                literal: "Sources/Extras/iOS/Project/*.h",
                path: "/subspecs/0/ios/project_header_files"
            ),
        ])

        #expect(inspection.unsupportedFields == [
            PodspecUnsupportedField(path: "/ios", kind: .deferredCocoaPodsSemantic),
            PodspecUnsupportedField(path: "/static_library", kind: .unknownField),
            PodspecUnsupportedField(path: "/subspecs/0", kind: .deferredCocoaPodsSemantic),
            PodspecUnsupportedField(
                path: "/subspecs/0/ios",
                kind: .deferredCocoaPodsSemantic
            ),
        ])
    }

    @Test("Keep root and root-platform module map states separate")
    func moduleMapStates() throws {
        let inspection = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0",
          "module_map": true,
          "ios": {"module_map": false},
          "osx": {"module_map": "Modules/macOS.modulemap"}
        }
        """#)

        #expect(inspection.podspec.root.declarations.linkage.moduleMap ==
            PodspecModuleMapDeclaration(value: .generated, path: "/module_map"))
        let ios = try #require(inspection.podspec.root.platformScopes.first {
            $0.platform == .iOS
        })
        #expect(ios.declarations.linkage.moduleMap ==
            PodspecModuleMapDeclaration(value: .disabled, path: "/ios/module_map"))
        let macOS = try #require(inspection.podspec.root.platformScopes.first {
            $0.platform == .macOS
        })
        #expect(macOS.declarations.linkage.moduleMap == PodspecModuleMapDeclaration(
            value: .customPath("Modules/macOS.modulemap"),
            path: "/osx/module_map"
        ))
        #expect(inspection.unsupportedFields == [
            PodspecUnsupportedField(path: "/ios", kind: .deferredCocoaPodsSemantic),
            PodspecUnsupportedField(path: "/osx", kind: .deferredCocoaPodsSemantic),
        ])
    }

    @Test("Preserve opaque paths, order, duplicates, and empty arrays")
    func opaqueDeclarations() throws {
        let inspection = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0",
          "frameworks": [],
          "vendored_frameworks": [
            "../Missing/**/*.xcframework",
            "Symlink.framework",
            "../Missing/**/*.xcframework",
            "Archive.zip"
          ],
          "vendored_libraries": ["libThing.a", "libThing.dylib", "NotALibrary.txt"],
          "project_header_files": "../../Headers/**/*.h"
        }
        """#)

        let linkage = inspection.podspec.root.declarations.linkage
        #expect(linkage.frameworks.isEmpty)
        #expect(linkage.vendoredFrameworks.map(\.literal) == [
            "../Missing/**/*.xcframework",
            "Symlink.framework",
            "../Missing/**/*.xcframework",
            "Archive.zip",
        ])
        #expect(linkage.vendoredFrameworks.map(\.path) == [
            "/vendored_frameworks/0",
            "/vendored_frameworks/1",
            "/vendored_frameworks/2",
            "/vendored_frameworks/3",
        ])
        #expect(linkage.vendoredLibraries.map(\.literal) == [
            "libThing.a",
            "libThing.dylib",
            "NotALibrary.txt",
        ])
        #expect(linkage.projectHeaders.count == 1)
        #expect(linkage.projectHeaders.first?.literal == "../../Headers/**/*.h")
        #expect(inspection.unsupportedFields.isEmpty)
    }

    @Test("Reject root-only declarations outside their version-bound scopes")
    func invalidDeclarationScopes() {
        let cases: [(json: String, path: String, expected: String)] = [
            (
                #"{"name":"Example","version":"1.0","subspecs":[{"name":"Core","module_name":"Core"}]}"#,
                "/subspecs/0/module_name",
                "absent because module_name is a root-only, non-platform declaration"
            ),
            (
                #"{"name":"Example","version":"1.0","ios":{"module_name":"ExampleIOS"}}"#,
                "/ios/module_name",
                "absent because module_name is a root-only, non-platform declaration"
            ),
            (
                #"{"name":"Example","version":"1.0","subspecs":[{"name":"Core","module_map":true}]}"#,
                "/subspecs/0/module_map",
                "absent because module_map is a root-only declaration"
            ),
            (
                #"{"name":"Example","version":"1.0","subspecs":[{"name":"Core","ios":{"module_map":false}}]}"#,
                "/subspecs/0/ios/module_map",
                "absent because module_map is a root-only declaration"
            ),
            (
                #"{"name":"Example","version":"1.0","subspecs":[{"name":"Core","static_framework":true}]}"#,
                "/subspecs/0/static_framework",
                "absent because static_framework is a root-only, non-platform declaration"
            ),
            (
                #"{"name":"Example","version":"1.0","ios":{"static_framework":true}}"#,
                "/ios/static_framework",
                "absent because static_framework is a root-only, non-platform declaration"
            ),
        ]

        for invalidCase in cases {
            #expect(error(for: invalidCase.json) == .invalidValue(
                path: invalidCase.path,
                expected: invalidCase.expected
            ))
        }
    }

    @Test("Reject malformed and empty linkage declaration values at exact paths")
    func malformedDeclarationValues() {
        let cases: [(fragment: String, path: String, expected: String)] = [
            (
                #""frameworks": {}"#,
                "/frameworks",
                "a non-empty string or an array of non-empty strings"
            ),
            (
                #""frameworks": ["Foundation", 1]"#,
                "/frameworks/1",
                "a non-empty string"
            ),
            (
                #""weak_frameworks": "  \n""#,
                "/weak_frameworks",
                "a non-empty string"
            ),
            (
                #""vendored_frameworks": null"#,
                "/vendored_frameworks",
                "a non-empty string or an array of non-empty strings"
            ),
            (
                #""vendored_libraries": ["libGood.a", ""]"#,
                "/vendored_libraries/1",
                "a non-empty string"
            ),
            (
                #""module_name": []"#,
                "/module_name",
                "a non-empty string"
            ),
            (
                #""module_map": 1"#,
                "/module_map",
                "a non-empty path string or a boolean"
            ),
            (
                #""module_map": " ""#,
                "/module_map",
                "a non-empty string"
            ),
            (
                #""header_dir": false"#,
                "/header_dir",
                "a non-empty string"
            ),
            (
                #""header_mappings_dir": "\t""#,
                "/header_mappings_dir",
                "a non-empty string"
            ),
            (
                #""project_header_files": ["Headers/A.h", {}]"#,
                "/project_header_files/1",
                "a non-empty string"
            ),
            (
                #""static_framework": 1"#,
                "/static_framework",
                "a boolean"
            ),
            (
                #""static_framework": null"#,
                "/static_framework",
                "a boolean"
            ),
        ]

        for invalidCase in cases {
            let json = "{\"name\":\"Example\",\"version\":\"1.0\",\(invalidCase.fragment)}"
            #expect(error(for: json) == .invalidValue(
                path: invalidCase.path,
                expected: invalidCase.expected
            ))
        }
    }

    @Test("Treat duplicate modeled declarations as a typed conflict")
    func duplicateDeclarationConflict() {
        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0",
          "module_map": true,
          "module_map": false
        }
        """#) == .duplicateObjectKey(path: "/module_map"))
    }

    @Test("Keep unsupported static_library evidence without inferring a conflict")
    func unsupportedStaticLibrary() throws {
        let inspection = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0",
          "static_framework": true,
          "static_library": false
        }
        """#)

        #expect(inspection.podspec.root.declarations.linkage.staticFramework ==
            PodspecBooleanDeclaration(value: true, path: "/static_framework"))
        #expect(inspection.unsupportedFields == [
            PodspecUnsupportedField(path: "/static_library", kind: .unknownField),
        ])
    }

    @Test("Keep deterministic Codable output and decode the earlier empty shape")
    func deterministicAndBackwardCodable() throws {
        let first = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0",
          "frameworks": ["Foundation", "CoreGraphics"],
          "module_map": true,
          "static_framework": false
        }
        """#)
        let second = try inspect(#"""
        {
          "static_framework": false,
          "module_map": true,
          "frameworks": ["Foundation", "CoreGraphics"],
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
        #expect(String(decoding: firstBytes, as: UTF8.self).contains(#""linkage":"#))
        #expect(try JSONDecoder().decode(PodspecInspection.self, from: firstBytes) == first)

        let allModuleMapStates = try PodspecJSONInspector().inspect(
            json: fixtureData(named: "LinkageModules-3.0.0.podspec")
        )
        let allModuleMapBytes = try encoder.encode(allModuleMapStates)
        #expect(try JSONDecoder().decode(
            PodspecInspection.self,
            from: allModuleMapBytes
        ) == allModuleMapStates)

        let earlierShape = Data(#"""
        {
          "sourceFiles": [],
          "publicHeaders": [],
          "privateHeaders": [],
          "resources": [],
          "resourceBundles": [],
          "dependencies": []
        }
        """#.utf8)
        let decoded = try JSONDecoder().decode(PodspecScopedDeclarations.self, from: earlierShape)
        #expect(decoded.linkage == .empty)

        let nullLinkage = Data(#"""
        {
          "sourceFiles": [],
          "publicHeaders": [],
          "privateHeaders": [],
          "resources": [],
          "resourceBundles": [],
          "dependencies": [],
          "linkage": null
        }
        """#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PodspecScopedDeclarations.self, from: nullLinkage)
        }
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
