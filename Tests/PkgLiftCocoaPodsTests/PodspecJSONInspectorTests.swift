import CryptoKit
import Foundation
import Testing
@testable import PkgLiftCocoaPods

@Suite("PodspecJSONInspector Tests")
struct PodspecJSONInspectorTests {
    @Test("Inspect bounded scalar and array Podspec declarations deterministically")
    func inspectSupportedDeclarations() throws {
        let json = #"""
        {
          "version": "1.2.3",
          "name": "ExampleKit",
          "platforms": {
            "watchos": null,
            "osx": "10.15",
            "ios": "13.0"
          },
          "source_files": "../Sources/**/*.swift",
          "public_header_files": ["Headers/Public/*.h", "Headers/Umbrella.h"],
          "private_header_files": "Headers/Private/*.h",
          "resources": ["Resources/en.lproj", "Resources/../Shared.json"],
          "resource_bundles": {
            "Secondary": "Resources/Secondary.xcassets",
            "Primary/Assets~Dark": ["Resources/Primary/*.png", "Resources/PrivacyInfo.xcprivacy"]
          },
          "summary": "Descriptive metadata is explicitly non-semantic here"
        }
        """#

        let inspection = try inspect(json)

        #expect(inspection.podspec.name == "ExampleKit")
        #expect(inspection.podspec.version == "1.2.3")
        #expect(inspection.podspec.platforms == [
            PodspecPlatformRequirement(platform: .iOS, minimumVersion: "13.0"),
            PodspecPlatformRequirement(platform: .macOS, minimumVersion: "10.15"),
            PodspecPlatformRequirement(platform: .watchOS, minimumVersion: nil),
        ])
        #expect(inspection.podspec.sourceFiles == ["../Sources/**/*.swift"])
        #expect(inspection.podspec.publicHeaders == [
            "Headers/Public/*.h",
            "Headers/Umbrella.h",
        ])
        #expect(inspection.podspec.privateHeaders == ["Headers/Private/*.h"])
        #expect(inspection.podspec.resources == [
            "Resources/en.lproj",
            "Resources/../Shared.json",
        ])
        #expect(inspection.podspec.resourceBundles == [
            PodspecResourceBundle(
                name: "Primary/Assets~Dark",
                resources: [
                    "Resources/Primary/*.png",
                    "Resources/PrivacyInfo.xcprivacy",
                ]
            ),
            PodspecResourceBundle(
                name: "Secondary",
                resources: ["Resources/Secondary.xcassets"]
            ),
        ])
        #expect(inspection.unsupportedFields.isEmpty)
    }

    @Test("Require non-empty string name and version fields")
    func requiredFields() {
        #expect(error(for: #"{"version":"1.0.0"}"#) == .missingRequiredField(path: "/name"))
        #expect(error(for: #"{"name":"Example"}"#) == .missingRequiredField(path: "/version"))
        #expect(error(for: #"{"name":" ","version":"1.0.0"}"#) == .invalidValue(
            path: "/name",
            expected: "a non-empty string"
        ))
        #expect(error(for: #"{"name":"Example","version":1}"#) == .invalidValue(
            path: "/version",
            expected: "a non-empty string"
        ))
    }

    @Test("Reject malformed JSON and non-object roots")
    func malformedAndNonObjectRoots() {
        #expect(error(for: "{") == .malformedJSON)
        #expect(error(for: "[]") == .rootMustBeObject(path: ""))
        #expect(error(for: #""Example""#) == .rootMustBeObject(path: ""))
    }

    @Test("Reject duplicate object keys before Foundation materializes JSON")
    func duplicateObjectKeys() {
        #expect(error(for: #"""
        {
          "name": "First",
          "na\u006de": "Second",
          "version": "1.0.0"
        }
        """#) == .duplicateObjectKey(path: "/name"))

        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0.0",
          "platforms": {"ios": "12.0", "i\u006fs": "13.0"}
        }
        """#) == .duplicateObjectKey(path: "/platforms/ios"))

        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0.0",
          "resource_bundles": {"Foo": "A.png", "F\u006fo": "B.png"}
        }
        """#) == .duplicateObjectKey(path: "/resource_bundles/Foo"))
    }

    @Test("Accept the standard JSON scalar grammar during the bounded pre-scan")
    func standardJSONScalarGrammar() throws {
        let inspection = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0.0",
          "description": "quote: \" slash: \/ backslash: \\ controls: \b\f\n\r\t unicode: \u03bc rocket: \ud83d\ude80",
          "license": {
            "values": [0, -0, 12, -1.5, 6.02e23, -2E-3, true, false, null, [], {}]
          }
        }
        """#)

        #expect(inspection.podspec.name == "Example")
        #expect(inspection.unsupportedFields.isEmpty)
    }

    @Test("Reject malformed JSON tokens during the bounded pre-scan")
    func malformedJSONTokens() {
        let malformedDocuments = [
            #"{"name":"Example","version":"1.0.0","summary":01}"#,
            #"{"name":"Example","version":"1.0.0","summary":1.}"#,
            #"{"name":"Example","version":"1.0.0","summary":1e}"#,
            #"{"name":"Example","version":"1.0.0","summary":"\q"}"#,
            #"{"name":"Example","version":"1.0.0","summary":[1,]}"#,
            #"{"name":"Example","version":"1.0.0","summary":{"value":1,}}"#,
            "{\"name\":\"Bad\nName\",\"version\":\"1.0.0\"}",
        ]

        for document in malformedDocuments {
            #expect(error(for: document) == .malformedJSON)
        }
    }

    @Test("Report exact paths for malformed scalar-or-array declarations")
    func malformedPathDeclarations() {
        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0.0",
          "source_files": ["Sources/A.swift", 42]
        }
        """#) == .invalidValue(
            path: "/source_files/1",
            expected: "a non-empty string"
        ))

        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0.0",
          "resource_bundles": {
            "Primary/Assets~Dark": ["Resources/A.png", {}]
          }
        }
        """#) == .invalidValue(
            path: "/resource_bundles/Primary~1Assets~0Dark/1",
            expected: "a non-empty string"
        ))
    }

    @Test("Separate known deferred semantics from unknown fields")
    func unsupportedFieldsAreFailClosedAndDeterministic() throws {
        let inspection = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0.0",
          "summary": "Ignored descriptive metadata",
          "dependencies": {"OtherKit": [">= 1.0"]},
          "custom/field~x": true,
          "platforms": {
            "ios": "13.0",
            "win/dows~": "10"
          }
        }
        """#)

        #expect(inspection.unsupportedFields == [
            PodspecUnsupportedField(
                path: "/custom~1field~0x",
                kind: .unknownField
            ),
            PodspecUnsupportedField(
                path: "/dependencies",
                kind: .deferredCocoaPodsSemantic
            ),
            PodspecUnsupportedField(
                path: "/platforms/win~1dows~0",
                kind: .unknownField
            ),
        ])
        #expect(inspection.podspec.platforms == [
            PodspecPlatformRequirement(platform: .iOS, minimumVersion: "13.0"),
        ])
    }

    @Test("Reject malformed supported platform values at their exact path")
    func malformedPlatformValue() {
        #expect(error(for: #"""
        {
          "name": "Example",
          "version": "1.0.0",
          "platforms": {"ios": 13}
        }
        """#) == .invalidValue(
            path: "/platforms/ios",
            expected: "a non-empty version string or null"
        ))
    }

    @Test("Round-trip the public inspection model through Codable")
    func codableRoundTrip() throws {
        let inspection = try inspect(#"""
        {
          "name": "Example",
          "version": "1.0.0",
          "source_files": ["Sources/**/*.swift"],
          "dependencies": {"OtherKit": []}
        }
        """#)

        let encoded = try JSONEncoder().encode(inspection)
        let decoded = try JSONDecoder().decode(PodspecInspection.self, from: encoded)
        #expect(decoded == inspection)
    }

    @Test("Inspect exact pinned CocoaPods Specs fixtures without network access")
    func pinnedCocoaPodsSpecsFixtures() throws {
        let keychainData = try fixtureData(named: "KeychainAccess-4.2.2.podspec")
        let deviceKitData = try fixtureData(named: "DeviceKit-5.8.0.podspec")
        let cryptoSwiftData = try fixtureData(named: "CryptoSwift-1.10.0.podspec")

        #expect(sha256(keychainData) == "4608b1366f705163ed9804e812bec02925bf6b61bd9924b08c482eb2be34187c")
        #expect(sha256(deviceKitData) == "8297066280041cd75175167c32d79ee772a4b95a29c85ffc99cd468a6f3f15a5")
        #expect(sha256(cryptoSwiftData) == "e1da64dfdf81fa8aef911b44cb6ae36f05f2cf18dc36c3176070ff1d0eb73257")

        let keychain = try PodspecJSONInspector().inspect(json: keychainData)
        #expect(keychain.podspec.name == "KeychainAccess")
        #expect(keychain.podspec.version == "4.2.2")
        #expect(keychain.podspec.sourceFiles == ["Lib/KeychainAccess/*.swift"])
        #expect(keychain.unsupportedFields.map(\.path) == [
            "/requires_arc",
            "/source",
            "/swift_version",
            "/swift_versions",
        ])

        let deviceKit = try PodspecJSONInspector().inspect(json: deviceKitData)
        #expect(deviceKit.podspec.resourceBundles == [
            PodspecResourceBundle(
                name: "DeviceKit",
                resources: ["Source/PrivacyInfo.xcprivacy"]
            ),
        ])
        #expect(deviceKit.podspec.platforms.contains(
            PodspecPlatformRequirement(platform: .watchOS, minimumVersion: "7.0")
        ))

        let cryptoSwift = try PodspecJSONInspector().inspect(json: cryptoSwiftData)
        #expect(cryptoSwift.podspec.resourceBundles == [
            PodspecResourceBundle(
                name: "CryptoSwift",
                resources: ["Sources/CryptoSwiftResources/PrivacyInfo.xcprivacy"]
            ),
        ])
        #expect(cryptoSwift.unsupportedFields.contains(
            PodspecUnsupportedField(
                path: "/cocoapods_version",
                kind: .deferredCocoaPodsSemantic
            )
        ))
    }

    @Test("Enforce byte, depth, collection, value, and UTF-8 string limits")
    func inspectionLimits() {
        let minimal = #"{"name":"Example","version":"1.0.0"}"#
        let minimalBytes = Data(minimal.utf8).count
        #expect(error(
            for: minimal,
            limits: limits(maximumJSONBytes: minimalBytes - 1)
        ) == .inputExceedsLimit(actual: minimalBytes, maximum: minimalBytes - 1))

        #expect(error(
            for: #"{"name":"Example","version":"1.0.0","unknown":{"child":true}}"#,
            limits: limits(maximumNestingDepth: 1)
        ) == .limitExceeded(path: "/unknown/child", actual: 2, maximum: 1))

        #expect(error(
            for: #"{"name":"Example","version":"1.0.0","source_files":["1","2","3","4"]}"#,
            limits: limits(maximumContainerElements: 3)
        ) == .limitExceeded(path: "/source_files", actual: 4, maximum: 3))

        #expect(error(
            for: minimal,
            limits: limits(maximumTotalValues: 2)
        ) == .limitExceeded(path: "/version", actual: 3, maximum: 2))

        #expect(error(
            for: minimal,
            limits: limits(maximumStringUTF8Bytes: 6)
        ) == .limitExceeded(path: "/name", actual: 7, maximum: 6))

        var deeplyNested = "true"
        for _ in 0..<65 {
            deeplyNested = "{\"a\":\(deeplyNested)}"
        }
        #expect(error(for: deeplyNested) == .limitExceeded(
            path: String(repeating: "/a", count: 65),
            actual: 65,
            maximum: 64
        ))
    }

    @Test("Reject invalid inspection limits with typed errors")
    func invalidLimits() {
        #expect(error(
            for: #"{"name":"Example","version":"1.0.0"}"#,
            limits: limits(maximumJSONBytes: 0)
        ) == .invalidLimit(name: "maximumJSONBytes", value: 0))

        #expect(error(
            for: #"{"name":"Example","version":"1.0.0"}"#,
            limits: limits(maximumNestingDepth: -1)
        ) == .invalidLimit(name: "maximumNestingDepth", value: -1))

        let excessiveDepth = PodspecInspectionLimits.maximumSupportedNestingDepth + 1
        #expect(error(
            for: #"{"name":"Example","version":"1.0.0"}"#,
            limits: limits(maximumNestingDepth: excessiveDepth)
        ) == .invalidLimit(name: "maximumNestingDepth", value: excessiveDepth))
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

    private func limits(
        maximumJSONBytes: Int = 1_048_576,
        maximumNestingDepth: Int = 64,
        maximumContainerElements: Int = 4_096,
        maximumTotalValues: Int = 16_384,
        maximumStringUTF8Bytes: Int = 65_536
    ) -> PodspecInspectionLimits {
        PodspecInspectionLimits(
            maximumJSONBytes: maximumJSONBytes,
            maximumNestingDepth: maximumNestingDepth,
            maximumContainerElements: maximumContainerElements,
            maximumTotalValues: maximumTotalValues,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes
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
}
