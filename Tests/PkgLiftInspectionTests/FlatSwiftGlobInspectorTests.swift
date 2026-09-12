import CryptoKit
import Foundation
import Testing
@testable import PkgLiftCocoaPods
@testable import PkgLiftInspection

@Suite("Flat Swift glob inspection", .serialized)
struct FlatSwiftGlobInspectorTests {
    @Test("Expands immediate Swift files in declaration and ASCII path order")
    func expandsFlatSwiftGlob() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSource(Data("struct Z {}\n".utf8), at: "Sources/Z.swift")
        try fixture.writeSource(Data("struct A {}\n".utf8), at: "Sources/A.swift")
        try fixture.writeSource(Data("struct Nested {}\n".utf8), at: "Sources/Nested/N.swift")
        try fixture.writeSource(Data("struct Hidden {}\n".utf8), at: "Sources/.Hidden.swift")
        try fixture.writeSource(Data("struct Upper {}\n".utf8), at: "Sources/Upper.SWIFT")
        try fixture.writeSource(Data("struct B {}\n".utf8), at: "Other/B.swift")
        try fixture.writePodspec(try podspecData(sourceFiles: ["Sources/*.swift", "Other/*.swift"]))

        let report = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(report.status == .verifiedObservedBytes)
        #expect(report.sources.count == 3)
        #expect(report.sources.map(\.declarationIndex) == [0, 0, 1])
        #expect(report.sources.map(\.byteCount) == [12, 12, 12])
        #expect(report.sources.map(\.pathSHA256) == ["Sources/A.swift", "Sources/Z.swift", "Other/B.swift"].map {
            sha256(Data($0.utf8))
        })
        #expect(report.selectionProfile == "root-literals-and-flat-swift-globs/v1")
        #expect(report.pathProfile == "ascii-relative-path/v2")
        #expect(report.schemaVersion == 2)
    }

    @Test("Opt-in literal selection uses v2 while the default remains v1")
    func optInLiteralProfile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSource(Data("struct A {}\n".utf8), at: "Sources/A.swift")
        try fixture.writePodspec(try podspecData(sourceFiles: ["Sources/A.swift"]))

        let legacy = inspect(fixture)
        let v2 = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(legacy.schemaVersion == 1)
        #expect(legacy.providerProfile == "pkglift.local-source-inspection/v1")
        #expect(legacy.pathProfile == "ascii-relative-path/v1")
        #expect(legacy.selectionProfile == nil)
        #expect(v2.schemaVersion == 2)
        #expect(v2.providerProfile == "pkglift.local-source-inspection/v2")
        #expect(v2.pathProfile == "ascii-relative-path/v2")
        #expect(v2.selectionProfile == "root-literals-and-flat-swift-globs/v1")
        #expect(v2.sources == legacy.sources)
    }

    @Test("V2 accepts plus signs in literal paths, glob directories and expanded filenames")
    func v2PlusPaths() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let path = "Sources+/Foo+Extensions.swift"
        try fixture.writeSource(Data(), at: path)

        try fixture.writePodspec(try podspecData(sourceFiles: [path]))
        let literal = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(literal.status == .verifiedObservedBytes)
        #expect(literal.sources.map(\.pathSHA256) == [sha256(Data(path.utf8))])
        #expect(literal.pathProfile == "ascii-relative-path/v2")

        try fixture.writePodspec(try podspecData(sourceFiles: ["Sources+/*.swift"]))
        let glob = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(glob.status == .verifiedObservedBytes)
        #expect(glob.sources.count == 1)
        #expect(glob.sources.map(\.pathSHA256) == [sha256(Data(path.utf8))])
        #expect(glob.pathProfile == "ascii-relative-path/v2")
    }

    @Test("Default v1 rejects plus paths while v2 treats plus-star as unsupported glob")
    func v1PlusCompatibilityAndV2GlobRefusal() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSource(Data(), at: "Sources+/Foo+Extensions.swift")

        try fixture.writePodspec(try podspecData(sourceFiles: ["Sources+/Foo+Extensions.swift"]))
        let legacy = inspect(fixture)
        #expect(legacy.status == .unavailable)
        #expect(legacy.reasons.contains { $0.code == .invalidSourcePath })
        #expect(legacy.pathProfile == "ascii-relative-path/v1")

        try fixture.writePodspec(try podspecData(sourceFiles: ["+*.swift"]))
        let v2 = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(v2.status == .unsupportedSelection)
        #expect(v2.reasons.contains { $0.code == .unsupportedGlob })
        #expect(v2.pathProfile == "ascii-relative-path/v2")
    }

    @Test("Inventory hash binds the v2 profile independently of the report")
    func v2InventoryHashOracle() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sourcePath = "Sources/A.swift"
        let source = Data("struct A {}\n".utf8)
        try fixture.writeSource(source, at: sourcePath)
        let podspec = try podspecData(sourceFiles: [sourcePath])
        try fixture.writePodspec(podspec)

        let report = inspect(fixture, mode: .flatSwiftGlobs)
        let expected = try inventorySHA256(
            providerProfile: "pkglift.local-source-inspection/v2",
            selectionProfile: "root-literals-and-flat-swift-globs/v1",
            podspecSHA256: sha256(podspec),
            sources: report.sources
        )
        #expect(report.inventorySHA256 == expected)
        #expect(report.sources.first?.contentSHA256 == sha256(source))
    }

    @Test("Flat mode preserves declaration assessment and does not authorize migration")
    func preservesAssessment() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let podspec = try podspecData(sourceFiles: ["Sources/*.swift"], additions: [
            "platforms": ["ios": "13.0"],
            "swift_version": "5.1",
            "requires_arc": true,
            "resource_bundles": ["Resources": ["PrivacyInfo.xcprivacy"]],
        ])
        try fixture.writeSource(Data("struct A {}\n".utf8), at: "Sources/A.swift")
        try fixture.writePodspec(podspec)
        let inspection = try PodspecJSONInspector().inspect(json: podspec)
        let expected = try PodspecSwiftPMAssessor().assess(
            inspection, cocoaPodsProfile: .cocoaPodsCore1_17_0,
            swiftPMProfile: .swiftToolsVersion6_0
        )

        let report = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(report.assessment == expected)
        #expect(report.packageValidity == "notAssessed")
        #expect(report.migrationEligibility == "notAssessed")
        #expect(report.origin == "notVerified")
    }

    @Test("V2 mixed selection retains both scope refusal and glob refusal")
    func mixedRefusalReasons() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(try podspecData(
            sourceFiles: ["Sources/**/*.swift"],
            additions: ["subspecs": [["name": "Core", "source_files": ["Sources/A.swift"]]]]
        ))
        let report = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(report.status == .unsupportedSelection)
        #expect(report.reasons.contains { $0.code == .unsupportedGlob })
        #expect(report.reasons.contains { $0.code == .ambiguousScope })
        #expect(report.pathProfile == "ascii-relative-path/v2")
        #expect(report.sources.isEmpty)
        #expect(report.inventorySHA256 == nil)
    }

    @Test("Recursive and unsupported glob syntax remain refusals", arguments: [
        "Sources/**/*.swift", "Sources/?.swift", "Sources/[A].swift", "Sources/{A}.swift",
    ])
    func unsupportedGlob(pattern: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSource(Data("struct A {}\n".utf8), at: "Sources/A.swift")
        try fixture.writePodspec(try podspecData(sourceFiles: [pattern]))

        let report = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(report.status == .unsupportedSelection)
        #expect(report.reasons.contains { $0.code == .unsupportedGlob })
        #expect(report.sources.isEmpty)
        #expect(report.inventorySHA256 == nil)
        #expect(report.pathProfile == "ascii-relative-path/v2")
    }

    @Test("Empty flat glob is unavailable with noSourceMatches")
    func emptyGlob() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSource(Data("struct A {}\n".utf8), at: "Nested/A.swift")
        try fixture.createDirectory("Sources")
        try fixture.writePodspec(try podspecData(sourceFiles: ["Sources/*.swift"]))

        let report = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(report.status == .unavailable)
        #expect(report.exitCode == 1)
        #expect(report.reasons.contains { $0.code == .noSourceMatches })
        #expect(report.pathProfile == "ascii-relative-path/v2")
        #expect(report.sources.isEmpty)
        #expect(report.inventorySHA256 == nil)
    }

    @Test("Literal and glob overlap and case collision fail closed")
    func overlapAndCaseCollision() throws {
        let cases = [["Sources/*.swift", "Sources/A.swift"], ["Sources/*.swift", "sources/a.swift"]]
        for paths in cases {
            let fixture = try Fixture()
            defer { fixture.remove() }
            try fixture.writeSource(Data("struct A {}\n".utf8), at: "Sources/A.swift")
            try fixture.writePodspec(try podspecData(sourceFiles: paths))
            let report = inspect(fixture, mode: .flatSwiftGlobs)
            #expect(report.status == .unavailable)
            #expect(report.sources.isEmpty)
            #expect(report.inventorySHA256 == nil)
            #expect(report.reasons.contains { $0.code == .duplicateSourcePath })
        }
    }

    @Test("Rejects unsafe paths and non-ASCII syntax", arguments: [
        "Sources/é.swift", "Sources/../A.swift", "Sources/A\u{0}.swift",
    ])
    func rejectsGlobGrammar(path: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(try podspecData(sourceFiles: [path]))
        let report = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(report.status == .unavailable)
        #expect(report.exitCode == 1)
        #expect(report.selectionProfile == "root-literals-and-flat-swift-globs/v1")
        #expect(report.sources.isEmpty)
        #expect(report.pathProfile == "ascii-relative-path/v2")
    }

    @Test("A root-level *.swift glob is outside the first profile")
    func rootGlobRefusal() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSource(Data("struct A {}\n".utf8), at: "A.swift")
        try fixture.writePodspec(try podspecData(sourceFiles: ["*.swift"]))
        let report = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(report.status == .unsupportedSelection)
        #expect(report.exitCode == 0)
        #expect(report.reasons.contains { $0.code == .unsupportedGlob })
        #expect(report.pathProfile == "ascii-relative-path/v2")
    }

    @Test("Hidden files and uppercase extensions are excluded without recursion")
    func hiddenAndUppercaseExcluded() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSource(Data("struct A {}\n".utf8), at: "Sources/A.swift")
        try fixture.writeSource(Data("struct H {}\n".utf8), at: "Sources/.Hidden.swift")
        try fixture.writeSource(Data("struct U {}\n".utf8), at: "Sources/U.SWIFT")
        try fixture.writeSource(Data("struct N {}\n".utf8), at: "Sources/Nested/N.swift")
        try fixture.writePodspec(try podspecData(sourceFiles: ["Sources/*.swift"]))
        let report = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(report.status == .verifiedObservedBytes)
        #expect(report.sources.count == 1)
    }

    @Test("Malformed v2 input remains privacy bounded and has no inventory")
    func malformedInput() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let data = Data(#"{"name":"secret","name":"duplicate","source_files":["Sources/*.swift"]}"#.utf8)
        try fixture.writePodspec(data)
        let report = inspect(fixture, mode: .flatSwiftGlobs)
        let json = String(decoding: try report.canonicalJSON(), as: UTF8.self)
        #expect(report.status == .unavailable)
        #expect(report.reasons.contains { $0.code == .invalidPodspec })
        #expect(report.selectionProfile != nil)
        #expect(report.pathProfile == "ascii-relative-path/v2")
        #expect(!json.contains("secret"))
        #expect(!json.contains(fixture.base.path))
    }

    @Test("More than 256 declarations is rejected before expansion")
    func declarationLimit() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let paths = (0..<257).map { "Sources/\($0).swift" }
        try fixture.writePodspec(try podspecData(sourceFiles: paths))
        let report = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(report.status == .unavailable)
        #expect(report.reasons.contains { $0.code == .limitExceeded })
        #expect(report.pathProfile == "ascii-relative-path/v2")
        #expect(report.sources.isEmpty)
    }

    @Test("Exactly 256 expanded source files succeeds and 257 refuses")
    func expandedSourceLimit() throws {
        for count in [256, 257] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            for index in 0..<count {
                try fixture.writeSource(Data(), at: "Sources/\(String(format: "%03d", index)).swift")
            }
            try fixture.writePodspec(try podspecData(sourceFiles: ["Sources/*.swift"]))
            let report = inspect(fixture, mode: .flatSwiftGlobs)
            #expect(report.status == (count == 256 ? .verifiedObservedBytes : .unavailable))
            #expect(report.sources.count == (count == 256 ? 256 : 0))
            if count == 257 { #expect(report.reasons.contains { $0.code == .limitExceeded }) }
        }
    }

    @Test("Exactly 16 glob directories succeeds and 17 refuses")
    func globDirectoryLimit() throws {
        for count in [16, 17] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            var patterns: [String] = []
            for index in 0..<count {
                let directory = "Dir\(index)"
                patterns.append("\(directory)/*.swift")
                try fixture.writeSource(Data(), at: "\(directory)/A.swift")
            }
            try fixture.writePodspec(try podspecData(sourceFiles: patterns))
            let report = inspect(fixture, mode: .flatSwiftGlobs)
            #expect(report.status == (count == 16 ? .verifiedObservedBytes : .unavailable))
            if count == 17 { #expect(report.reasons.contains { $0.code == .limitExceeded }) }
        }
    }

    @Test("A selected directory accepts 4096 entries and refuses 4097")
    func directoryEntryLimit() throws {
        for count in [4096, 4097] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            try fixture.writeSource(Data(), at: "Sources/A.swift")
            for index in 0..<(count - 1) {
                try fixture.writeSource(Data(), at: "Sources/entry-\(index).txt")
            }
            try fixture.writePodspec(try podspecData(sourceFiles: ["Sources/*.swift"]))
            let report = inspect(fixture, mode: .flatSwiftGlobs)
            #expect(report.status == (count == 4096 ? .verifiedObservedBytes : .unavailable))
            if count == 4097 { #expect(report.reasons.contains { $0.code == .limitExceeded }) }
        }
    }

    @Test("Exactly 8192 total entries across three directories succeeds and 8193 refuses")
    func totalEntryLimit() throws {
        for total in [8192, 8193] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            var patterns: [String] = []
            let counts = [total / 3, total / 3, total - (total / 3) * 2]
            for (directoryIndex, count) in counts.enumerated() {
                let directory = "Group\(directoryIndex)"
                patterns.append("\(directory)/*.swift")
                try fixture.writeSource(Data(), at: "\(directory)/A.swift")
                for entry in 0..<(count - 1) {
                    try fixture.writeSource(Data(), at: "\(directory)/entry-\(entry).txt")
                }
            }
            try fixture.writePodspec(try podspecData(sourceFiles: patterns))
            let report = inspect(fixture, mode: .flatSwiftGlobs)
            #expect(report.status == (total == 8192 ? .verifiedObservedBytes : .unavailable))
            if total == 8193 { #expect(report.reasons.contains { $0.code == .limitExceeded }) }
        }
    }

    @Test("Expanded path length is checked after a valid glob declaration")
    func expandedPathLimit() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = String(repeating: "a", count: 240)
        let second = String(repeating: "b", count: 240)
        let filename = String(repeating: "c", count: 40) + ".swift"
        let directory = "\(first)/\(second)"
        try fixture.writeSource(Data(), at: "\(directory)/\(filename)")
        let pattern = "\(directory)/*.swift"
        #expect(pattern.utf8.count <= 512)
        try fixture.writePodspec(try podspecData(sourceFiles: [pattern]))
        let report = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(report.status == .unavailable)
        #expect(report.reasons.contains { $0.code == .limitExceeded || $0.code == .invalidSourcePath })
        #expect(report.sources.isEmpty)
    }

    @Test("An oversized assessment keeps the v2 fallback profile and original document hash")
    func oversizedAssessmentFallback() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var scope: [String: Any] = [
            "name": "Leaf",
            "compiler_flags": Array(repeating: "-D", count: 4096),
        ]
        for _ in 0..<20 { scope = ["name": "Nested", "subspecs": [scope]] }
        let input = try podspecData(sourceFiles: ["Sources/A.swift"], additions: ["subspecs": [scope]])
        #expect(input.count < PodspecInspectionLimits.default.maximumJSONBytes)
        let assessment = try PodspecSwiftPMAssessor().assess(
            PodspecJSONInspector().inspect(json: input),
            cocoaPodsProfile: .cocoaPodsCore1_17_0, swiftPMProfile: .swiftToolsVersion6_0
        )
        #expect(try localInspectionJSON(assessment).count > PodspecInspectionLimits.default.maximumJSONBytes)
        try fixture.writePodspec(input)
        let report = inspect(fixture, mode: .flatSwiftGlobs)
        #expect(report.status == .unavailable)
        #expect(report.schemaVersion == 2)
        #expect(report.selectionProfile == "root-literals-and-flat-swift-globs/v1")
        #expect(report.pathProfile == "ascii-relative-path/v2")
        #expect(report.assessment == nil)
        #expect(report.sources.isEmpty)
        #expect(report.inventorySHA256 == nil)
        #expect(report.podspecSHA256 == sha256(input))
        #expect(report.reasons.map(\.code) == [.limitExceeded])
    }

    private func inspect(_ fixture: Fixture, mode: LocalSourceSelectionMode = .literalOnly) -> LocalSourceInspectionReport {
        LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.root.path,
            sourceSelection: mode
        )
    }

    private func podspecData(sourceFiles: [String], additions: [String: Any] = [:]) throws -> Data {
        var object: [String: Any] = ["name": "Example", "version": "1.0.0", "source_files": sourceFiles]
        for (key, value) in additions { object[key] = value }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func inventorySHA256(
        providerProfile: String, selectionProfile: String, podspecSHA256: String,
        sources: [LocalSourceInspectionReport.Source]
    ) throws -> String {
        struct Inventory: Encodable {
            let schemaVersion: Int
            let providerProfile: String
            let selectionProfile: String
            let pathProfile = "ascii-relative-path/v2"
            let podspecSHA256: String
            let sources: [LocalSourceInspectionReport.Source]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return sha256(try encoder.encode(Inventory(
            schemaVersion: 2, providerProfile: providerProfile,
            selectionProfile: selectionProfile, podspecSHA256: podspecSHA256, sources: sources
        )))
    }
}

private struct Fixture {
    let base: URL
    let root: URL
    let podspec: URL

    init() throws {
        base = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pkglift-flat-glob-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("SourceRoot", isDirectory: true)
        podspec = base.appendingPathComponent("Example.podspec.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func writePodspec(_ data: Data) throws { try data.write(to: podspec) }

    func writeSource(_ data: Data, at path: String) throws {
        let destination = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination)
    }

    func createDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(path), withIntermediateDirectories: true
        )
    }

    func remove() { try? FileManager.default.removeItem(at: base) }
}
