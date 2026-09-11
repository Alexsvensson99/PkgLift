import CryptoKit
import Darwin
import Foundation
import Testing
@testable import PkgLiftCocoaPods
@testable import PkgLiftInspection

@Suite("Local source inspector adversarial tests")
struct LocalSourceInspectorTests {
    @Test("Hash exact Podspec and literal source bytes while retaining the original assessment")
    func verifiedLiteralSource() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let sourcePath = "Sources/Device.swift"
        let source = Data("public enum Device {}\n".utf8)
        try fixture.writeSource(source, at: sourcePath)
        let podspec = try podspecData(
            sourceFiles: [sourcePath],
            additions: [
                "platforms": ["ios": "13.0"],
                "resource_bundles": ["DeviceKit": ["PrivacyInfo.xcprivacy"]],
                "source": [
                    "git": "https://user:secret@example.invalid/private.git",
                    "tag": "5.8.0",
                ],
                "swift_versions": ["5.9"],
                "requires_arc": true,
            ]
        )
        try fixture.writePodspec(podspec)

        let report = inspect(fixture)
        let observed = try #require(report.sources.first)
        let expectedAssessment = try PodspecSwiftPMAssessor().assess(
            PodspecJSONInspector().inspect(json: podspec),
            cocoaPodsProfile: .cocoaPodsCore1_17_0,
            swiftPMProfile: .swiftToolsVersion6_0
        )
        let expectedInventorySHA256 = try inventorySHA256(
            podspecSHA256: sha256(podspec),
            sources: report.sources
        )

        #expect(report.status == .verifiedObservedBytes)
        #expect(report.exitCode == 0)
        #expect(report.schemaVersion == 1)
        #expect(report.providerProfile == "pkglift.local-source-inspection/v1")
        #expect(report.pathProfile == "ascii-relative-path/v1")
        #expect(report.selectionCoverage == "declaredRootSourcesOnly")
        #expect(report.packageValidity == "notAssessed")
        #expect(report.migrationEligibility == "notAssessed")
        #expect(report.podspecSHA256 == sha256(podspec))
        #expect(report.assessment == expectedAssessment)
        #expect(observed.declarationIndex == 0)
        #expect(observed.pathSHA256 == sha256(Data(sourcePath.utf8)))
        #expect(observed.contentSHA256 == sha256(source))
        #expect(observed.byteCount == source.count)
        #expect(report.inventorySHA256 == expectedInventorySHA256)
        #expect(report.reasons.isEmpty)
        #expect(expectedAssessment.reasons.contains {
            $0.code == .sourceSelectionRequiresGeneratedMetadata
        })
        #expect(expectedAssessment.reasons.contains {
            $0.code == .resourceBundleRequiresGeneratedMetadata
        })
        #expect(expectedAssessment.reasons.contains {
            $0.code == .platformRequiresGeneratedMetadata
        })

        let canonicalData = try report.canonicalJSON()
        var scanner = PodspecJSONBoundaryScanner(
            data: canonicalData,
            limits: .default
        )
        try scanner.validate()
        let canonical = String(decoding: canonicalData, as: UTF8.self)
        #expect(canonical.contains(#""origin":"notVerified""#))
        #expect(canonical.contains(#""migrationEligibility":"notAssessed""#))
        #expect(!canonical.contains("pkglift.synthetic-local/v1"))
        #expect(!canonical.contains("AUTO"))
        #expect(!canonical.contains(fixture.root.path))
        #expect(!canonical.contains("user:secret"))
        #expect(!canonical.contains("private.git"))
        #expect(!canonical.contains(sourcePath))
        #expect(!canonical.contains(String(decoding: source, as: UTF8.self)))
    }

    @Test("Canonical output is byte-identical across different roots")
    func deterministicAcrossRoots() throws {
        let first = try Fixture()
        let second = try Fixture()
        defer {
            first.remove()
            second.remove()
        }

        let paths = ["Sources/B.swift", "Sources/A.swift"]
        let podspec = try podspecData(sourceFiles: paths)
        for fixture in [first, second] {
            try fixture.writePodspec(podspec)
            try fixture.writeSource(Data("struct B {}\n".utf8), at: paths[0])
            try fixture.writeSource(Data("struct A {}\n".utf8), at: paths[1])
        }

        let firstReport = inspect(first)
        let secondReport = inspect(second)

        #expect(firstReport.status == .verifiedObservedBytes)
        #expect(secondReport.status == .verifiedObservedBytes)
        #expect(firstReport.sources.map(\.declarationIndex) == [0, 1])
        #expect(firstReport.sources == secondReport.sources)
        #expect(firstReport.inventorySHA256 == secondReport.inventorySHA256)
        #expect(try firstReport.canonicalJSON() == secondReport.canonicalJSON())
    }

    @Test("Refuse every glob even when it currently matches exactly one file", arguments: [
        "Sources/*.swift",
        "Sources/?.swift",
        "Sources/[A].swift",
        "Sources/{A}.swift",
    ])
    func singletonGlob(pattern: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSource(Data("struct A {}\n".utf8), at: "Sources/A.swift")
        try fixture.writePodspec(podspecData(sourceFiles: [pattern]))

        let report = inspect(fixture)

        expectRefusal(report, status: .unsupportedSelection, code: .unsupportedGlob)
        #expect(report.exitCode == 0)
    }

    @Test("Preserve Swift version normalization assessment beside a root glob refusal")
    func swiftSoupLikeMultipleLimitations() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let podspec = try podspecData(
            sourceFiles: ["Sources/**/*.swift"],
            additions: [
                "swift_versions": ["4.0", "5.1"],
                "swift_version": "5.1",
            ]
        )
        try fixture.writePodspec(podspec)
        let expectedAssessment = try PodspecSwiftPMAssessor().assess(
            PodspecJSONInspector().inspect(json: podspec),
            cocoaPodsProfile: .cocoaPodsCore1_17_0,
            swiftPMProfile: .swiftToolsVersion6_0
        )

        let report = inspect(fixture)

        #expect(report.status == .unsupportedSelection)
        #expect(report.exitCode == 0)
        #expect(report.podspecSHA256 == sha256(podspec))
        #expect(report.assessment == expectedAssessment)
        #expect(expectedAssessment.reasons.contains {
            $0.code == .sourceSelectionRequiresGeneratedMetadata
        })
        #expect(expectedAssessment.reasons.contains {
            $0.code == .swiftVersionRequiresInspection
        })
        #expect(report.reasons.map(\.code) == [
            .unknownSelectionSemantics,
            .unsupportedGlob,
        ])
        #expect(report.reasons.map(\.declarationIndex) == [nil, 0])
        #expect(report.sources.isEmpty)
        #expect(report.inventorySHA256 == nil)
        #expect(report.migrationEligibility == "notAssessed")
    }

    @Test("Valid CocoaPods selectors outside the literal root subset are unsupported")
    func unsupportedSelectionSurfaces() throws {
        let cases: [(String, [String: Any], LocalSourceInspectionReport.Reason.Code)] = [
            (
                "subspec",
                ["subspecs": [["name": "Core", "source_files": ["Sources/A.swift"]]]],
                .ambiguousScope
            ),
            ("exclude", ["exclude_files": ["Sources/A.swift"]], .excludedSources),
            (
                "platform override",
                ["ios": ["source_files": ["Sources/A.swift"]]],
                .ambiguousScope
            ),
            ("unknown selector", ["future_build_input": true], .unknownSelectionSemantics),
        ]

        for (label, additions, expectedCode) in cases {
            let fixture = try Fixture(label: label)
            defer { fixture.remove() }
            try fixture.writeSource(Data("struct A {}\n".utf8), at: "Sources/A.swift")
            try fixture.writePodspec(podspecData(
                sourceFiles: ["Sources/A.swift"],
                additions: additions
            ))

            let report = inspect(fixture)
            expectRefusal(report, status: .unsupportedSelection, code: expectedCode)
            #expect(report.exitCode == 0)
        }
    }

    @Test("Reject unsafe, non-ASCII and overlong source declarations")
    func invalidSourceDeclarations() throws {
        let longPath = [
            String(repeating: "a", count: 170),
            String(repeating: "b", count: 170),
            String(repeating: "c", count: 165) + ".swift",
        ].joined(separator: "/")
        #expect(longPath.utf8.count > 512)

        let cases: [(String, LocalSourceInspectionReport.Reason.Code)] = [
            ("/private/tmp/Absolute.swift", .invalidSourcePath),
            ("../Outside.swift", .invalidSourcePath),
            ("Sources/../Outside.swift", .invalidSourcePath),
            ("Sources/A\u{0}.swift", .invalidSourcePath),
            ("Sourcés/A.swift", .invalidSourcePath),
            (longPath, .limitExceeded),
        ]

        for (path, expectedCode) in cases {
            let fixture = try Fixture(label: expectedCode.rawValue)
            defer { fixture.remove() }
            try fixture.writePodspec(podspecData(sourceFiles: [path]))

            expectRefusal(inspect(fixture), status: .unavailable, code: expectedCode)
        }
    }

    @Test("Treat a valid non-Swift literal as an unsupported source type")
    func unsupportedSourceType() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(podspecData(sourceFiles: ["Sources/A.m"]))

        let report = inspect(fixture)

        expectRefusal(report, status: .unsupportedSelection, code: .unsupportedSourceType)
        #expect(report.exitCode == 0)
    }

    @Test("A later unsafe path overrides an earlier unsupported glob")
    func invalidPathAfterGlob() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(podspecData(sourceFiles: [
            "Sources/*.swift",
            "../Outside.swift",
        ]))

        let report = inspect(fixture)

        expectRefusal(
            report,
            status: .unavailable,
            code: .invalidSourcePath,
            declarationIndex: 1
        )
        #expect(report.exitCode == 1)
    }

    @Test("A later case collision overrides an earlier unsupported source type")
    func duplicatePathAfterUnsupportedType() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(podspecData(sourceFiles: [
            "Sources/Legacy.m",
            "Sources/A.swift",
            "sources/a.swift",
        ]))

        let report = inspect(fixture)

        expectRefusal(
            report,
            status: .unavailable,
            code: .duplicateSourcePath,
            declarationIndex: 2
        )
        #expect(report.exitCode == 1)
    }

    @Test("Treat an absent root source declaration as a completed unsupported selection")
    func missingSourceSelection() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(podspecData(sourceFiles: []))

        let report = inspect(fixture)

        expectRefusal(report, status: .unsupportedSelection, code: .missingSourceSelection)
        #expect(report.exitCode == 0)
    }

    @Test("Reject more than 256 declared source files before producing inventory")
    func sourceCountLimit() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let paths = (0...256).map { "Sources/File\($0).swift" }
        try fixture.writePodspec(podspecData(sourceFiles: paths))

        expectRefusal(inspect(fixture), status: .unavailable, code: .limitExceeded)
    }

    @Test("Reject duplicate and case-fold-colliding source paths")
    func duplicateSourcePaths() throws {
        let cases = [
            ["Sources/A.swift", "Sources/A.swift"],
            ["Sources/A.swift", "sources/a.SWIFT"],
        ]

        for paths in cases {
            let fixture = try Fixture()
            defer { fixture.remove() }
            try fixture.writePodspec(podspecData(sourceFiles: paths))

            expectRefusal(inspect(fixture), status: .unavailable, code: .duplicateSourcePath)
        }
    }

    @Test("Do not escape through a sibling whose name shares the source-root prefix")
    func rootPrefixCollision() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sibling = fixture.root.deletingLastPathComponent()
            .appendingPathComponent(fixture.root.lastPathComponent + "-secret", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sibling) }
        try Data("private\n".utf8).write(to: sibling.appendingPathComponent("A.swift"))
        try fixture.writePodspec(podspecData(sourceFiles: ["../\(sibling.lastPathComponent)/A.swift"]))

        let report = inspect(fixture)

        expectRefusal(report, status: .unavailable, code: .invalidSourcePath)
        #expect(!String(decoding: try report.canonicalJSON(), as: UTF8.self).contains("secret"))
    }

    @Test("A failed later source yields no partial inventory")
    func noPartialInventory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeSource(Data("struct A {}\n".utf8), at: "Sources/A.swift")
        try fixture.writePodspec(podspecData(sourceFiles: [
            "Sources/A.swift",
            "Sources/Missing.swift",
        ]))

        let report = inspect(fixture)

        expectRefusal(report, status: .unavailable, code: .missingInput, declarationIndex: 1)
    }

    @Test("Reject missing Podspec, source root and selected source")
    func missingInputs() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(podspecData(sourceFiles: ["Sources/Missing.swift"]))
        expectRefusal(inspect(fixture), status: .unavailable, code: .missingInput)

        let missingPodspec = LocalSourceInspector().inspect(
            podspecPath: fixture.base.appendingPathComponent("Missing.podspec.json").path,
            sourceRoot: fixture.root.path
        )
        expectRefusal(missingPodspec, status: .unavailable, code: .missingInput)

        let missingRoot = LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.base.appendingPathComponent("MissingRoot").path
        )
        expectRefusal(missingRoot, status: .unavailable, code: .missingInput)
    }

    @Test("Reject nonregular Podspec, root and source objects")
    func nonRegularInputs() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(podspecData(sourceFiles: ["Sources/A.swift"]))
        try FileManager.default.createDirectory(
            at: fixture.root.appendingPathComponent("Sources/A.swift", isDirectory: true),
            withIntermediateDirectories: true
        )
        expectRefusal(inspect(fixture), status: .unavailable, code: .nonRegularFile)

        let directoryPodspec = fixture.base.appendingPathComponent("Directory.podspec.json")
        try FileManager.default.createDirectory(at: directoryPodspec, withIntermediateDirectories: true)
        let podspecReport = LocalSourceInspector().inspect(
            podspecPath: directoryPodspec.path,
            sourceRoot: fixture.root.path
        )
        expectRefusal(podspecReport, status: .unavailable, code: .nonRegularFile)

        let fileRoot = fixture.base.appendingPathComponent("FileRoot")
        try Data("not a directory".utf8).write(to: fileRoot)
        let rootReport = LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fileRoot.path
        )
        expectRefusal(rootReport, status: .unavailable, code: .nonRegularFile)
    }

    @Test("Reject a symlink source root and symlink components beneath it")
    func sourceSymlinks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(podspecData(sourceFiles: ["Sources/A.swift"]))

        let linkedRoot = fixture.base.appendingPathComponent("LinkedRoot")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: fixture.root)
        let rootReport = LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: linkedRoot.path
        )
        expectRefusal(rootReport, status: .unavailable, code: .symbolicLink)

        let outside = fixture.base.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("struct A {}\n".utf8).write(to: outside.appendingPathComponent("A.swift"))
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("Sources"),
            withDestinationURL: outside
        )
        let ancestorReport = inspect(fixture)
        expectRefusal(ancestorReport, status: .unavailable, code: .symbolicLink)
    }

    @Test("Reject a final source-file symlink")
    func finalSourceSymlink() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.base.appendingPathComponent("Outside.swift")
        try Data("struct Outside {}\n".utf8).write(to: outside)
        let source = fixture.root.appendingPathComponent("Sources/A.swift")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outside)
        try fixture.writePodspec(podspecData(sourceFiles: ["Sources/A.swift"]))

        expectRefusal(inspect(fixture), status: .unavailable, code: .symbolicLink)
    }

    @Test("Reject Podspec symlinks in the final component and an ancestor")
    func podspecSymlinks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let data = try podspecData(sourceFiles: ["Sources/A.swift"])
        try fixture.writePodspec(data)

        let finalLink = fixture.base.appendingPathComponent("Linked.podspec.json")
        try FileManager.default.createSymbolicLink(at: finalLink, withDestinationURL: fixture.podspec)
        expectRefusal(
            LocalSourceInspector().inspect(podspecPath: finalLink.path, sourceRoot: fixture.root.path),
            status: .unavailable,
            code: .symbolicLink
        )

        let actualParent = fixture.base.appendingPathComponent("ActualParent", isDirectory: true)
        try FileManager.default.createDirectory(at: actualParent, withIntermediateDirectories: true)
        let nestedPodspec = actualParent.appendingPathComponent("Spec.json")
        try data.write(to: nestedPodspec)
        let linkedParent = fixture.base.appendingPathComponent("LinkedParent")
        try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: actualParent)
        expectRefusal(
            LocalSourceInspector().inspect(
                podspecPath: linkedParent.appendingPathComponent("Spec.json").path,
                sourceRoot: fixture.root.path
            ),
            status: .unavailable,
            code: .symbolicLink
        )
    }

    @Test("Reject a source-root path with a symlink ancestor")
    func sourceRootSymlinkAncestor() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(podspecData(sourceFiles: ["Sources/A.swift"]))
        try fixture.writeSource(Data("struct A {}\n".utf8), at: "Sources/A.swift")
        let actualParent = fixture.base.appendingPathComponent("RootParent", isDirectory: true)
        try FileManager.default.createDirectory(at: actualParent, withIntermediateDirectories: true)
        let actualRoot = actualParent.appendingPathComponent("Root", isDirectory: true)
        try FileManager.default.moveItem(at: fixture.root, to: actualRoot)
        let linkedParent = fixture.base.appendingPathComponent("LinkedRootParent")
        try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: actualParent)

        let report = LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: linkedParent.appendingPathComponent("Root").path
        )

        expectRefusal(report, status: .unavailable, code: .symbolicLink)
    }

    @Test("Refuse FIFO inputs without trying to stream from them")
    func fifoRefusal() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(podspecData(sourceFiles: ["Sources/Pipe.swift"]))
        let fifo = fixture.root.appendingPathComponent("Sources/Pipe.swift")
        try FileManager.default.createDirectory(
            at: fifo.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let result = fifo.path.withCString { Darwin.mkfifo($0, 0o600) }
        #expect(result == 0)
        guard result == 0 else { return }

        expectRefusal(inspect(fixture), status: .unavailable, code: .nonRegularFile)

        let podspecFIFO = fixture.base.appendingPathComponent("Pipe.podspec.json")
        let podspecResult = podspecFIFO.path.withCString { Darwin.mkfifo($0, 0o600) }
        #expect(podspecResult == 0)
        guard podspecResult == 0 else { return }
        expectRefusal(
            LocalSourceInspector().inspect(
                podspecPath: podspecFIFO.path,
                sourceRoot: fixture.root.path
            ),
            status: .unavailable,
            code: .nonRegularFile
        )
    }

    @Test("Reject an unreadable selected source")
    func unreadableSource() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("Sources/A.swift")
        try fixture.writeSource(Data("struct A {}\n".utf8), at: "Sources/A.swift")
        try fixture.writePodspec(podspecData(sourceFiles: ["Sources/A.swift"]))
        #expect(source.path.withCString { Darwin.chmod($0, 0) } == 0)
        defer { _ = source.path.withCString { Darwin.chmod($0, 0o600) } }

        expectRefusal(inspect(fixture), status: .unavailable, code: .unreadableInput)
    }

    @Test("Reject a sparse source larger than the per-file byte cap")
    func sparseOversizedSource() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(podspecData(sourceFiles: ["Sources/Large.swift"]))
        let source = fixture.root.appendingPathComponent("Sources/Large.swift")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        #expect(FileManager.default.createFile(atPath: source.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(16 * 1_024 * 1_024 + 1))
        try handle.close()

        expectRefusal(inspect(fixture), status: .unavailable, code: .limitExceeded)
    }

    @Test("Reject a sparse Podspec larger than the existing JSON byte cap")
    func sparseOversizedPodspec() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(FileManager.default.createFile(atPath: fixture.podspec.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: fixture.podspec)
        try handle.truncate(atOffset: UInt64(
            PodspecInspectionLimits.default.maximumJSONBytes + 1
        ))
        try handle.close()

        let report = inspect(fixture)

        expectRefusal(report, status: .unavailable, code: .limitExceeded)
        #expect(report.podspecSHA256 == nil)
    }

    @Test("Reject an inventory whose complete sources exceed the total byte cap")
    func totalSourceByteLimit() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let paths = (0..<5).map { "Sources/Large\($0).swift" }
        try fixture.writePodspec(podspecData(sourceFiles: paths))
        for (index, path) in paths.enumerated() {
            let source = fixture.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: source.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            #expect(FileManager.default.createFile(atPath: source.path, contents: Data()))
            let handle = try FileHandle(forWritingTo: source)
            let size = index < 4 ? 16 * 1_024 * 1_024 : 1
            try handle.truncate(atOffset: UInt64(size))
            try handle.close()
        }

        expectRefusal(inspect(fixture), status: .unavailable, code: .limitExceeded)
    }

    @Test("Enforce the source cap against bytes that grow after streaming starts")
    func growingSourceCrossesCap() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("Sources/Growing.swift")
        try fixture.writeSource(Data("x".utf8), at: "Sources/Growing.swift")
        try fixture.writePodspec(podspecData(sourceFiles: ["Sources/Growing.swift"]))

        let inspector = LocalSourceInspector { event in
            guard event == .afterSourceChunk(0),
                  let handle = try? FileHandle(forWritingTo: source) else { return }
            try? handle.truncate(atOffset: UInt64(16 * 1_024 * 1_024 + 1))
            try? handle.close()
        }
        let report = inspector.inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.root.path
        )

        expectRefusal(report, status: .unavailable, code: .limitExceeded)
    }

    @Test("Reject same-byte source replacement after it was read")
    func sourceReplacementAfterRead() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("Sources/A.swift")
        let backup = fixture.base.appendingPathComponent("Original.swift")
        let bytes = Data("struct A {}\n".utf8)
        try fixture.writeSource(bytes, at: "Sources/A.swift")
        try fixture.writePodspec(podspecData(sourceFiles: ["Sources/A.swift"]))

        let inspector = LocalSourceInspector { event in
            guard event == .afterSourceRead(0) else { return }
            try? FileManager.default.moveItem(at: source, to: backup)
            try? bytes.write(to: source)
        }
        let report = inspector.inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.root.path
        )

        #expect(FileManager.default.fileExists(atPath: backup.path))
        expectRefusal(report, status: .unavailable, code: .changedDuringRead)
    }

    @Test("Reject same-byte Podspec replacement after it was read")
    func podspecReplacementAfterRead() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backup = fixture.base.appendingPathComponent("Original.podspec.json")
        let podspec = try podspecData(sourceFiles: ["Sources/A.swift"])
        try fixture.writeSource(Data("struct A {}\n".utf8), at: "Sources/A.swift")
        try fixture.writePodspec(podspec)

        let inspector = LocalSourceInspector { event in
            guard event == .afterPodspecRead else { return }
            try? FileManager.default.moveItem(at: fixture.podspec, to: backup)
            try? podspec.write(to: fixture.podspec)
        }
        let report = inspector.inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.root.path
        )

        #expect(FileManager.default.fileExists(atPath: backup.path))
        expectRefusal(report, status: .unavailable, code: .changedDuringRead)
    }

    @Test("Reject replacement of the source-root binding before final validation")
    func sourceRootReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let movedRoot = fixture.base.appendingPathComponent("OriginalRoot", isDirectory: true)
        let sourcePath = "Sources/A.swift"
        try fixture.writeSource(Data("struct A {}\n".utf8), at: sourcePath)
        try fixture.writePodspec(podspecData(sourceFiles: [sourcePath]))

        let inspector = LocalSourceInspector { event in
            guard event == .beforeFinalValidation else { return }
            try? FileManager.default.moveItem(at: fixture.root, to: movedRoot)
            try? FileManager.default.createDirectory(
                at: fixture.root.appendingPathComponent("Sources"),
                withIntermediateDirectories: true
            )
            try? Data("struct Replacement {}\n".utf8).write(
                to: fixture.root.appendingPathComponent(sourcePath)
            )
        }
        let report = inspector.inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.root.path
        )

        #expect(FileManager.default.fileExists(atPath: movedRoot.path))
        expectRefusal(report, status: .unavailable, code: .changedDuringRead)
    }

    @Test("Reject replacement of an ancestor above the source root with same-byte contents")
    func sourceRootAncestorReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let capabilityParent = fixture.base.appendingPathComponent(
            "CapabilityParent",
            isDirectory: true
        )
        let sourceRoot = capabilityParent.appendingPathComponent("NestedRoot", isDirectory: true)
        let sourcePath = "Sources/A.swift"
        let sourceBytes = Data("struct A {}\n".utf8)
        let originalParent = fixture.base.appendingPathComponent(
            "OriginalCapabilityParent",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceRoot.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        try sourceBytes.write(to: sourceRoot.appendingPathComponent(sourcePath))
        try fixture.writePodspec(podspecData(sourceFiles: [sourcePath]))

        let inspector = LocalSourceInspector { event in
            guard event == .beforeFinalValidation else { return }
            try? FileManager.default.moveItem(at: capabilityParent, to: originalParent)
            try? FileManager.default.createDirectory(
                at: sourceRoot.appendingPathComponent("Sources"),
                withIntermediateDirectories: true
            )
            try? sourceBytes.write(to: sourceRoot.appendingPathComponent(sourcePath))
        }
        let report = inspector.inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: sourceRoot.path
        )

        #expect(FileManager.default.fileExists(atPath: originalParent.path))
        expectRefusal(report, status: .unavailable, code: .changedDuringRead)
    }

    @Test("Reject replacement of a selected source ancestor with same-byte contents")
    func selectedSourceAncestorReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sourcePath = "Sources/A.swift"
        let sourceBytes = Data("struct A {}\n".utf8)
        let sourceDirectory = fixture.root.appendingPathComponent("Sources", isDirectory: true)
        let originalDirectory = fixture.base.appendingPathComponent(
            "OriginalSources",
            isDirectory: true
        )
        try fixture.writeSource(sourceBytes, at: sourcePath)
        try fixture.writePodspec(podspecData(sourceFiles: [sourcePath]))

        let inspector = LocalSourceInspector { event in
            guard event == .beforeFinalValidation else { return }
            try? FileManager.default.moveItem(at: sourceDirectory, to: originalDirectory)
            try? FileManager.default.createDirectory(
                at: sourceDirectory,
                withIntermediateDirectories: true
            )
            try? sourceBytes.write(to: fixture.root.appendingPathComponent(sourcePath))
        }
        let report = inspector.inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.root.path
        )

        #expect(FileManager.default.fileExists(atPath: originalDirectory.path))
        expectRefusal(report, status: .unavailable, code: .changedDuringRead)
    }

    @Test("Reject NULs and traversal in explicit Podspec and source-root arguments")
    func invalidInputPaths() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writePodspec(podspecData(sourceFiles: ["Sources/A.swift"]))

        let badPodspec = LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path + "\u{0}ignored",
            sourceRoot: fixture.root.path
        )
        expectRefusal(badPodspec, status: .unavailable, code: .invalidInputPath)

        let badRoot = LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.root.path + "\u{0}ignored"
        )
        expectRefusal(badRoot, status: .unavailable, code: .invalidInputPath)

        let traversingPodspec = LocalSourceInspector().inspect(
            podspecPath: fixture.base.path + "/../" + fixture.podspec.lastPathComponent,
            sourceRoot: fixture.root.path
        )
        expectRefusal(traversingPodspec, status: .unavailable, code: .invalidInputPath)

        let traversingRoot = LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.base.path + "/../" + fixture.root.lastPathComponent
        )
        expectRefusal(traversingRoot, status: .unavailable, code: .invalidInputPath)
    }

    @Test("Malformed and duplicate-key Podspecs fail closed with privacy-bounded JSON")
    func invalidPodspecAndPrivacy() throws {
        let documents = [
            Data(#"{"name":"Example","version":"1","source_files":["Sources/A.swift"]"#.utf8),
            Data(#"""
            {
              "name": "First",
              "na\u006de": "/Users/alex/private",
              "version": "1",
              "source_files": ["Sources/A.swift"]
            }
            """#.utf8),
        ]

        for document in documents {
            let fixture = try Fixture()
            defer { fixture.remove() }
            try fixture.writePodspec(document)

            let report = inspect(fixture)
            expectRefusal(report, status: .unavailable, code: .invalidPodspec)
            #expect(report.podspecSHA256 == sha256(document))
            let canonical = String(decoding: try report.canonicalJSON(), as: UTF8.self)
            #expect(!canonical.contains(fixture.base.path))
            #expect(!canonical.contains("/Users/alex/private"))
            #expect(!canonical.contains("First"))
        }
    }

    private func inspect(_ fixture: Fixture) -> LocalSourceInspectionReport {
        LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.root.path
        )
    }

    private func expectRefusal(
        _ report: LocalSourceInspectionReport,
        status: LocalSourceInspectionReport.Status,
        code: LocalSourceInspectionReport.Reason.Code,
        declarationIndex: Int? = nil
    ) {
        #expect(report.status == status)
        #expect(report.sources.isEmpty)
        #expect(report.inventorySHA256 == nil)
        #expect(report.reasons.contains {
            $0.code == code && (declarationIndex == nil || $0.declarationIndex == declarationIndex)
        })
    }

    private func podspecData(
        sourceFiles: [String],
        additions: [String: Any] = [:]
    ) throws -> Data {
        var object: [String: Any] = [
            "name": "Example",
            "version": "1.0.0",
            "source_files": sourceFiles,
        ]
        for (key, value) in additions { object[key] = value }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func inventorySHA256(
        podspecSHA256: String,
        sources: [LocalSourceInspectionReport.Source]
    ) throws -> String {
        struct Inventory: Encodable {
            let schemaVersion = 1
            let providerProfile = "pkglift.local-source-inspection/v1"
            let pathProfile = "ascii-relative-path/v1"
            let podspecSHA256: String
            let sources: [LocalSourceInspectionReport.Source]
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return sha256(try encoder.encode(Inventory(
            podspecSHA256: podspecSHA256,
            sources: sources
        )))
    }
}

private struct Fixture {
    let base: URL
    let root: URL
    let podspec: URL

    init(label: String = "fixture") throws {
        // `/tmp` and `/var` are symlink aliases on macOS. Start from the
        // physical namespace so fixtures do not weaken the production rule
        // that rejects symlink components in caller-supplied capabilities.
        let canonicalTemporaryDirectory = URL(
            fileURLWithPath: "/private/tmp",
            isDirectory: true
        )
        let safeLabel = label
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        base = canonicalTemporaryDirectory.appendingPathComponent(
            "pkglift-local-inspector-\(safeLabel)-\(UUID().uuidString)",
            isDirectory: true
        )
        root = base.appendingPathComponent("SourceRoot", isDirectory: true)
        podspec = base.appendingPathComponent("Example.podspec.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func writePodspec(_ data: Data) throws {
        try data.write(to: podspec)
    }

    func writeSource(_ data: Data, at path: String) throws {
        let destination = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination)
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }
}
