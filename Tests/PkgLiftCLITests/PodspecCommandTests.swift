import Foundation
import XCTest
@testable import PkgLiftCLI
import PkgLiftInspection

final class PodspecCommandTests: XCTestCase {
    func testParsesOnlyExplicitInspectionOptions() throws {
        let command = try PodspecInspectCommand.parse([
            "--podspec", "/tmp/example.podspec.json",
            "--source-root", "/tmp/example-source",
            "--format", "json",
        ])

        XCTAssertEqual(command.podspecPath, "/tmp/example.podspec.json")
        XCTAssertEqual(command.sourceRoot, "/tmp/example-source")
        XCTAssertEqual(command.format.rawValue, "json")
    }

    func testRequiresBothExplicitInputOptions() {
        XCTAssertThrowsError(try PodspecInspectCommand.parse([
            "--podspec", "/tmp/example.podspec.json",
        ])) { error in
            XCTAssertTrue(PodspecInspectCommand.message(for: error).contains("--source-root"))
        }

        XCTAssertThrowsError(try PodspecInspectCommand.parse([
            "--source-root", "/tmp/example-source",
        ])) { error in
            XCTAssertTrue(PodspecInspectCommand.message(for: error).contains("--podspec"))
        }
    }

    func testRejectsUnknownOutputFormatWithArgumentParserUsage() {
        XCTAssertThrowsError(try PodspecInspectCommand.parse([
            "--podspec", "/tmp/example.podspec.json",
            "--source-root", "/tmp/example-source",
            "--format", "yaml",
        ])) { error in
            XCTAssertTrue(PodspecInspectCommand.message(for: error).contains("--format"))
        }
    }

    func testRootAndInspectHelpRegisterTheNestedCommand() {
        XCTAssertTrue(PkgLift.helpMessage(includeHidden: false, columns: 120).contains("podspec"))

        let help = PkgLift.helpMessage(
            for: PodspecInspectCommand.self,
            includeHidden: false,
            columns: 120
        )
        XCTAssertTrue(help.contains("podspec inspect"))
        XCTAssertTrue(help.contains("--podspec"))
        XCTAssertTrue(help.contains("--source-root"))
        XCTAssertTrue(help.contains("--format"))
    }

    func testTextReportDescribesObservedBytesWithoutLeakingInputs() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let report = LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.sourceRoot.path
        )
        let output = try PodspecInspectCommand.render(report, format: .text)

        XCTAssertEqual(report.status.rawValue, "verifiedObservedBytes")
        XCTAssertEqual(report.exitCode, 0)
        XCTAssertTrue(output.contains("Local source inspection: verifiedObservedBytes"))
        XCTAssertTrue(output.contains("Origin: notVerified"))
        XCTAssertTrue(output.contains("Package validity: notAssessed"))
        XCTAssertTrue(output.contains("Migration eligibility: notAssessed"))
        XCTAssertTrue(output.contains("declaration #0: 23 bytes"))
        XCTAssertTrue(output.contains("Observed bytes do not establish SwiftPM compatibility, provenance, or migration approval."))
        XCTAssertFalse(output.contains(fixture.root.path))
        XCTAssertFalse(output.contains("Source/Example.swift"))
        XCTAssertFalse(output.contains("input-secret"))
    }

    func testTextReportIncludesDistinctCanonicalAssessmentEvidencePaths() throws {
        let fixture = try makeFixture(includePlatforms: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let report = LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.sourceRoot.path
        )
        let output = try PodspecInspectCommand.render(report, format: .text)

        XCTAssertEqual(report.status.rawValue, "verifiedObservedBytes")
        XCTAssertTrue(output.contains("[platformRequiresGeneratedMetadata] /platforms/ios"))
        XCTAssertTrue(output.contains("[platformRequiresGeneratedMetadata] /platforms/osx"))
        XCTAssertFalse(output.contains(fixture.root.path))
        XCTAssertFalse(output.contains("input-secret"))
        XCTAssertFalse(output.contains("Source/Example.swift"))
    }

    func testJSONReportUsesCanonicalReportAndRedactsLocalInputs() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let report = LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.sourceRoot.path
        )
        let output = try PodspecInspectCommand.render(report, format: .json)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["status"] as? String, "verifiedObservedBytes")
        XCTAssertEqual(object["origin"] as? String, "notVerified")
        XCTAssertEqual(object["packageValidity"] as? String, "notAssessed")
        XCTAssertEqual(object["migrationEligibility"] as? String, "notAssessed")
        XCTAssertNotNil(object["podspecSHA256"] as? String)
        XCTAssertNotNil(object["inventorySHA256"] as? String)
        XCTAssertEqual((object["sources"] as? [[String: Any]])?.count, 1)
        XCTAssertFalse(output.contains(fixture.root.path))
        XCTAssertFalse(output.contains("Source/Example.swift"))
        XCTAssertFalse(output.contains("input-secret"))
    }

    func testUnavailableReportKeepsAReportAndFailureExitCode() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.sourceRoot.appendingPathComponent("Source/Example.swift"))

        let report = LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.sourceRoot.path
        )
        let output = try PodspecInspectCommand.render(report, format: .text)

        XCTAssertEqual(report.status.rawValue, "unavailable")
        XCTAssertEqual(report.exitCode, 1)
        XCTAssertTrue(output.contains("Local source inspection: unavailable"))
        XCTAssertTrue(output.contains("Inspection reasons:"))
        XCTAssertFalse(output.contains(fixture.root.path))
    }

    func testUnsupportedGlobReturnsACompleteRefusalReportWithSuccessExitCode() throws {
        let fixture = try makeFixture(sourceFiles: "Source/*.swift")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let report = LocalSourceInspector().inspect(
            podspecPath: fixture.podspec.path,
            sourceRoot: fixture.sourceRoot.path
        )
        let output = try PodspecInspectCommand.render(report, format: .text)

        XCTAssertEqual(report.status.rawValue, "unsupportedSelection")
        XCTAssertEqual(report.exitCode, 0)
        XCTAssertTrue(report.sources.isEmpty)
        XCTAssertEqual(report.reasons.count, 1)
        XCTAssertEqual(report.reasons.first?.code.rawValue, "unsupportedGlob")
        XCTAssertEqual(report.reasons.first?.declarationIndex, 0)
        XCTAssertTrue(output.contains("Local source inspection: unsupportedSelection"))
        XCTAssertTrue(output.contains("[unsupportedGlob] declaration #0"))
        XCTAssertFalse(output.contains(fixture.root.path))
    }

    func testGlobExplanationPrecedesDeclarationDetailsAndKeepsJSONUnchanged() throws {
        let fixture = try makeFixture(sourceFiles: "Source/*.swift", includePlatforms: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let report = LocalSourceInspector().inspect(podspecPath: fixture.podspec.path, sourceRoot: fixture.sourceRoot.path)
        let jsonBefore = try report.canonicalJSON()
        let text = try PodspecInspectCommand.render(report, format: .text)
        XCTAssertTrue(text.hasPrefix("Source selection is not supported."))
        let reason = try XCTUnwrap(text.range(of: "does not expand glob patterns"))
        let details = try XCTUnwrap(text.range(of: "Declaration assessment:"))
        XCTAssertLessThan(reason.lowerBound, details.lowerBound)
        XCTAssertTrue(text.contains("Keep the original Podspec intact"))
        XCTAssertTrue(text.contains("zero-based source_files index"))
        XCTAssertEqual(try report.canonicalJSON(), jsonBefore)
        XCTAssertEqual(try PodspecInspectCommand.render(report, format: .json), String(decoding: jsonBefore, as: UTF8.self))
    }

    func testSubspecSourcesAreNotDescribedAsMissingProjectFiles() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let data = Data(#"{"name":"secret","version":"1.0.0","subspecs":[{"name":"Core","source_files":"Source/*.swift"}]}"#.utf8)
        try data.write(to: fixture.podspec)
        let report = LocalSourceInspector().inspect(podspecPath: fixture.podspec.path, sourceRoot: fixture.sourceRoot.path)
        let text = try PodspecInspectCommand.render(report, format: .text)
        XCTAssertEqual(report.status, .unsupportedSelection)
        XCTAssertTrue(text.contains("at the Podspec root"))
        XCTAssertTrue(text.contains("does not mean the project has no source files"))
        XCTAssertFalse(text.contains("Source/*.swift"))
        XCTAssertFalse(text.contains("secret"))
    }

    func testUnavailableSummaryDoesNotPromiseEmptyProjectOrPartialEvidence() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let report = LocalSourceInspector().inspect(podspecPath: fixture.podspec.path, sourceRoot: fixture.root.appendingPathComponent("absent").path)
        let text = try PodspecInspectCommand.render(report, format: .text)
        XCTAssertTrue(text.hasPrefix("Inspection could not complete."))
        XCTAssertTrue(text.contains("No partial source-file inventory is reported"))
        XCTAssertEqual(report.exitCode, 1)
        XCTAssertFalse(text.contains(fixture.root.path))
    }

    private func makeFixture(
        sourceFiles: String = "Source/Example.swift",
        includePlatforms: Bool = false
    ) throws -> Fixture {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(
            "PkgLiftPodspecCommand-\(UUID().uuidString)",
            isDirectory: true
        )
        let sourceRoot = root.appendingPathComponent("input-secret-source", isDirectory: true)
        let sourceDirectory = sourceRoot.appendingPathComponent("Source", isDirectory: true)
        let podspec = root.appendingPathComponent("input-secret.podspec.json", isDirectory: false)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sourceBytes = Data("public enum Example {}\n".utf8)
        XCTAssertEqual(sourceBytes.count, 23)
        try sourceBytes.write(
            to: sourceDirectory.appendingPathComponent("Example.swift")
        )
        var podspecObject: [String: Any] = [
            "name": "input-secret-name",
            "version": "1.0.0",
            "source": [
                "git": "https://input-secret@example.invalid/Example.git",
                "tag": "1.0.0",
            ],
            "source_files": [sourceFiles],
        ]
        if includePlatforms {
            podspecObject["platforms"] = ["ios": "13.0", "osx": "10.15"]
        }
        try JSONSerialization.data(withJSONObject: podspecObject, options: [.sortedKeys])
            .write(to: podspec)
        return Fixture(root: root, podspec: podspec, sourceRoot: sourceRoot)
    }
}

private struct Fixture {
    let root: URL
    let podspec: URL
    let sourceRoot: URL
}
