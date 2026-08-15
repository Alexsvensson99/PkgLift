import Foundation
import XCTest
import PkgLiftCore
@testable import PkgLiftCLI

final class DiagnosticsCommandTests: XCTestCase {
    func testParsesSelectionAndOutputOptions() throws {
        let command = try DiagnosticsCommand.parse([
            "--path", "/tmp/Project",
            "--workspace", "App.xcworkspace",
            "--project", "App.xcodeproj",
            "--output", "report.json",
            "--overwrite",
        ])

        XCTAssertEqual(command.common.path, "/tmp/Project")
        XCTAssertEqual(command.common.workspace, "App.xcworkspace")
        XCTAssertEqual(command.common.project, "App.xcodeproj")
        XCTAssertEqual(command.output, "report.json")
        XCTAssertTrue(command.overwrite)
    }

    func testRelativeOutputResolvesFromCurrentDirectory() throws {
        XCTAssertEqual(
            try DiagnosticsCommand.resolveOutputURL(
                "reports/pkglift.json",
                currentDirectory: "/tmp/Invocation"
            ).path,
            "/tmp/Invocation/reports/pkglift.json"
        )
    }

    func testControlCharactersAreRejected() {
        XCTAssertThrowsError(
            try DiagnosticsCommand.resolveOutputURL(
                "report\nother.json",
                currentDirectory: "/tmp"
            )
        )
    }

    func testInvalidProjectPathStillWritesAReviewablePartialReport() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftDiagnosticsCLI-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let missingProject = root.appendingPathComponent("Private Client Project")
        let output = root.appendingPathComponent("diagnostics.json")
        var command = try DiagnosticsCommand.parse([
            "--path", missingProject.path,
            "--output", output.path,
            "--no-color",
        ])

        try await command.run()

        let data = try Data(contentsOf: output)
        let report = try JSONDecoder().decode(DiagnosticsReport.self, from: data)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(report.status, .partial)
        XCTAssertEqual(report.failures.map(\.stage), [.discovery])
        XCTAssertFalse(json.contains(missingProject.path))
        XCTAssertEqual(report.project.root, "<PROJECT_ROOT>")
    }
}
