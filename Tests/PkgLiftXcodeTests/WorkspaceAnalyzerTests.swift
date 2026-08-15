import Foundation
import XCTest
@testable import PkgLiftXcode

final class WorkspaceAnalyzerTests: XCTestCase {
    func testResolvesNestedGroupAndContainerReferencesWithinRoot() throws {
        let root = try makeDirectory(prefix: "PkgLiftWorkspace")
        defer { try? FileManager.default.removeItem(at: root) }

        let appProject = root.appendingPathComponent("Projects/Nested/App.xcodeproj")
        let podsProject = root.appendingPathComponent("Pods/Pods.xcodeproj")
        try FileManager.default.createDirectory(at: appProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: podsProject, withIntermediateDirectories: true)

        let workspace = try makeWorkspace(
            at: root.appendingPathComponent("Workspaces/App.xcworkspace"),
            contents: """
            <?xml version="1.0" encoding="UTF-8"?>
            <Workspace version="1.0">
              <Group location="container:../Projects" name="Products">
                <Group location="group:Nested" name="Nested">
                  <FileRef location="group:App.xcodeproj"/>
                </Group>
              </Group>
              <FileRef location="container:../Pods/Pods.xcodeproj"/>
            </Workspace>
            """
        )

        let result = try WorkspaceAnalyzer().analyzeWorkspace(
            at: workspace.path,
            containedIn: root.path
        )

        XCTAssertEqual(result.projectPaths, [appProject.path])
        XCTAssertTrue(result.isCocoaPodsGenerated)
    }

    func testAcceptsAbsoluteProjectReferenceInsideRoot() throws {
        let root = try makeDirectory(prefix: "PkgLiftWorkspace")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("Projects/App.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let workspace = try makeWorkspace(
            at: root.appendingPathComponent("App.xcworkspace"),
            contents: workspaceXML(reference: "absolute:\(project.path)")
        )

        let result = try WorkspaceAnalyzer().analyzeWorkspace(
            at: workspace.path,
            containedIn: root.path
        )

        XCTAssertEqual(result.projectPaths, [project.path])
    }

    func testResolvesSelfReferenceForProjectWorkspace() throws {
        let root = try makeDirectory(prefix: "PkgLiftWorkspace")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("App.xcodeproj")
        let workspace = try makeWorkspace(
            at: project.appendingPathComponent("project.xcworkspace"),
            contents: workspaceXML(reference: "self:")
        )

        let result = try WorkspaceAnalyzer().analyzeWorkspace(
            at: workspace.path,
            containedIn: root.path
        )

        XCTAssertEqual(result.projectPaths, [project.path])
    }

    func testRejectsAbsoluteProjectReferenceOutsideRoot() throws {
        let root = try makeDirectory(prefix: "PkgLiftWorkspaceRoot")
        let outside = try makeDirectory(prefix: "PkgLiftWorkspaceOutside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let project = outside.appendingPathComponent("Outside.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let workspace = try makeWorkspace(
            at: root.appendingPathComponent("App.xcworkspace"),
            contents: workspaceXML(reference: "absolute:\(project.path)")
        )

        XCTAssertThrowsError(
            try WorkspaceAnalyzer().analyzeWorkspace(at: workspace.path, containedIn: root.path)
        ) { error in
            guard case WorkspaceAnalyzerError.projectReferenceOutsideRoot = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsRelativeAbsoluteProjectReference() throws {
        let root = try makeDirectory(prefix: "PkgLiftWorkspace")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try makeWorkspace(
            at: root.appendingPathComponent("App.xcworkspace"),
            contents: workspaceXML(reference: "absolute:App.xcodeproj")
        )

        XCTAssertThrowsError(
            try WorkspaceAnalyzer().analyzeWorkspace(at: workspace.path, containedIn: root.path)
        ) { error in
            guard case WorkspaceAnalyzerError.invalidAbsoluteLocation = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsSymlinkedProjectThatEscapesRoot() throws {
        let root = try makeDirectory(prefix: "PkgLiftWorkspaceRoot")
        let outside = try makeDirectory(prefix: "PkgLiftWorkspaceOutside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let outsideProject = outside.appendingPathComponent("Outside.xcodeproj")
        try FileManager.default.createDirectory(at: outsideProject, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Linked.xcodeproj"),
            withDestinationURL: outsideProject
        )
        let workspace = try makeWorkspace(
            at: root.appendingPathComponent("App.xcworkspace"),
            contents: workspaceXML(reference: "group:Linked.xcodeproj")
        )

        XCTAssertThrowsError(
            try WorkspaceAnalyzer().analyzeWorkspace(at: workspace.path, containedIn: root.path)
        ) { error in
            guard case WorkspaceAnalyzerError.projectReferenceOutsideRoot = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsUnsupportedProjectLocationScheme() throws {
        let root = try makeDirectory(prefix: "PkgLiftWorkspace")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try makeWorkspace(
            at: root.appendingPathComponent("App.xcworkspace"),
            contents: workspaceXML(reference: "developer:Library.xcodeproj")
        )

        XCTAssertThrowsError(
            try WorkspaceAnalyzer().analyzeWorkspace(at: workspace.path, containedIn: root.path)
        ) { error in
            guard case WorkspaceAnalyzerError.unsupportedLocationScheme("developer") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testFilesystemRootCanBeUsedAsContainmentRoot() throws {
        let root = try makeDirectory(prefix: "PkgLiftWorkspace")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("App.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let workspace = try makeWorkspace(
            at: root.appendingPathComponent("App.xcworkspace"),
            contents: workspaceXML(reference: "group:App.xcodeproj")
        )

        let result = try WorkspaceAnalyzer().analyzeWorkspace(
            at: workspace.path,
            containedIn: "/"
        )

        XCTAssertEqual(result.projectPaths, [project.path])
    }

    private func makeDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeWorkspace(at url: URL, contents: String) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try contents.write(
            to: url.appendingPathComponent("contents.xcworkspacedata"),
            atomically: true,
            encoding: .utf8
        )
        return url
    }

    private func workspaceXML(reference: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Workspace version="1.0">
          <FileRef location="\(reference)"/>
        </Workspace>
        """
    }
}
