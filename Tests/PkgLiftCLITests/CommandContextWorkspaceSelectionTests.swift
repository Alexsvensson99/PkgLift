import Foundation
import PathKit
import XCTest
import XcodeProj
@testable import PkgLiftCLI

final class CommandContextWorkspaceSelectionTests: XCTestCase {
    func testRecursivelyDiscoversSingleNestedProject() async throws {
        let root = try makeDirectory(prefix: "PkgLiftCLIRecursive")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("Products/App/App.xcodeproj")
        try makeProject(at: project, targetName: "App")

        let options = try CommonOptions.parse(["--path", root.path])
        let context = try await CommandContext.load(from: options)

        XCTAssertEqual(context.resolvedProjectPath, project.path)
        XCTAssertNil(context.resolvedWorkspacePath)
        XCTAssertFalse(context.isWorkspaceSelected)
    }

    func testSelectsExplicitProjectInsideMultiProjectWorkspace() async throws {
        let fixture = try makeMultiProjectWorkspace()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let options = try CommonOptions.parse([
            "--path", fixture.root.path,
            "--workspace", "Workspaces/Products.xcworkspace",
            "--project", "Projects/Tool.xcodeproj",
        ])

        let context = try await CommandContext.load(from: options)
        let analysis = context.buildProjectAnalysis()

        XCTAssertEqual(context.resolvedProjectPath, fixture.toolProject.path)
        XCTAssertEqual(context.resolvedWorkspacePath, fixture.workspace.path)
        XCTAssertTrue(context.isWorkspaceSelected)
        XCTAssertEqual(context.xcodeAnalysis?.projectInfo.targets.map(\.name), ["Tool"])
        XCTAssertEqual(analysis.project.projectPath, fixture.toolProject.path)
        XCTAssertEqual(analysis.project.workspacePath, fixture.workspace.path)
    }

    func testMultiProjectWorkspaceRequiresExplicitProject() async throws {
        let fixture = try makeMultiProjectWorkspace()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let options = try CommonOptions.parse([
            "--path", fixture.root.path,
            "--workspace", "Workspaces/Products.xcworkspace",
        ])

        do {
            _ = try await CommandContext.load(from: options)
            XCTFail("Expected ambiguous workspace project selection")
        } catch let error as CommandContextError {
            guard case .ambiguousWorkspaceProjects(let workspace, let projects) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(workspace, fixture.workspace.path)
            XCTAssertEqual(projects, [fixture.appProject.path, fixture.toolProject.path])
        }
    }

    func testExplicitProjectMustBeReferencedByWorkspace() async throws {
        let fixture = try makeMultiProjectWorkspace()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let unreferenced = fixture.root.appendingPathComponent("Projects/Unreferenced.xcodeproj")
        try makeProject(at: unreferenced, targetName: "Unreferenced")
        let options = try CommonOptions.parse([
            "--path", fixture.root.path,
            "--workspace", "Workspaces/Products.xcworkspace",
            "--project", "Projects/Unreferenced.xcodeproj",
        ])

        do {
            _ = try await CommandContext.load(from: options)
            XCTFail("Expected workspace membership refusal")
        } catch let error as CommandContextError {
            guard case .projectNotInWorkspace(let project, let workspace, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(project, unreferenced.path)
            XCTAssertEqual(workspace, fixture.workspace.path)
        }
    }

    func testExplicitProjectCannotEscapeSelectedRoot() async throws {
        let root = try makeDirectory(prefix: "PkgLiftCLIRoot")
        let outside = try makeDirectory(prefix: "PkgLiftCLIOutside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let outsideProject = outside.appendingPathComponent("Outside.xcodeproj")
        try makeProject(at: outsideProject, targetName: "Outside")
        let relativeEscape = "../\(outside.lastPathComponent)/Outside.xcodeproj"
        let options = try CommonOptions.parse([
            "--path", root.path,
            "--project", relativeEscape,
        ])

        do {
            _ = try await CommandContext.load(from: options)
            XCTFail("Expected containment refusal")
        } catch let error as CommandContextError {
            guard case .selectionOutsideRoot(_, let resolved, let selectedRoot) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(resolved, outsideProject.path)
            XCTAssertEqual(selectedRoot, root.path)
        }
    }

    func testExplicitWorkspaceCannotEscapeSelectedRoot() async throws {
        let root = try makeDirectory(prefix: "PkgLiftCLIRoot")
        let outside = try makeDirectory(prefix: "PkgLiftCLIOutside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let workspace = outside.appendingPathComponent("Outside.xcworkspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let relativeEscape = "../\(outside.lastPathComponent)/Outside.xcworkspace"
        let options = try CommonOptions.parse([
            "--path", root.path,
            "--workspace", relativeEscape,
        ])

        do {
            _ = try await CommandContext.load(from: options)
            XCTFail("Expected workspace containment refusal")
        } catch let error as CommandContextError {
            guard case .selectionOutsideRoot(_, let resolved, let selectedRoot) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(resolved, workspace.path)
            XCTAssertEqual(selectedRoot, root.path)
        }
    }

    func testExplicitProjectSymlinkCannotEscapeSelectedRoot() async throws {
        let root = try makeDirectory(prefix: "PkgLiftCLIRoot")
        let outside = try makeDirectory(prefix: "PkgLiftCLIOutside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let outsideProject = outside.appendingPathComponent("Outside.xcodeproj")
        try makeProject(at: outsideProject, targetName: "Outside")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Linked.xcodeproj"),
            withDestinationURL: outsideProject
        )
        let options = try CommonOptions.parse([
            "--path", root.path,
            "--project", "Linked.xcodeproj",
        ])

        do {
            _ = try await CommandContext.load(from: options)
            XCTFail("Expected symlink containment refusal")
        } catch let error as CommandContextError {
            guard case .selectionOutsideRoot(_, let resolved, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(resolved, outsideProject.path)
        }
    }

    private func makeMultiProjectWorkspace() throws -> (
        root: URL,
        workspace: URL,
        appProject: URL,
        toolProject: URL
    ) {
        let root = try makeDirectory(prefix: "PkgLiftCLIWorkspace")
        let appProject = root.appendingPathComponent("Projects/App.xcodeproj")
        let toolProject = root.appendingPathComponent("Projects/Tool.xcodeproj")
        try makeProject(at: appProject, targetName: "App")
        try makeProject(at: toolProject, targetName: "Tool")

        let workspace = root.appendingPathComponent("Workspaces/Products.xcworkspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <Workspace version="1.0">
          <FileRef location="container:../Projects/App.xcodeproj"/>
          <FileRef location="container:../Projects/Tool.xcodeproj"/>
        </Workspace>
        """.write(
            to: workspace.appendingPathComponent("contents.xcworkspacedata"),
            atomically: true,
            encoding: .utf8
        )
        return (root, workspace, appProject, toolProject)
    }

    private func makeDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeProject(at projectURL: URL, targetName: String) throws {
        let mainGroup = PBXGroup(children: [], sourceTree: .group, name: "Main")
        let projectConfigurations = XCConfigurationList()
        let targetConfigurations = XCConfigurationList()
        let frameworks = PBXFrameworksBuildPhase(files: [])
        let target = PBXNativeTarget(
            name: targetName,
            buildConfigurationList: targetConfigurations,
            buildPhases: [frameworks],
            productName: "\(targetName).app",
            productType: .application
        )
        let rootProject = PBXProject(
            name: targetName,
            buildConfigurationList: projectConfigurations,
            compatibilityVersion: "Xcode 15.0",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup,
            targets: [target]
        )
        let pbxproj = PBXProj(
            rootObject: rootProject,
            objectVersion: 56,
            archiveVersion: 1,
            classes: [:],
            objects: []
        )
        [mainGroup, projectConfigurations, targetConfigurations, frameworks, target, rootProject]
            .forEach { pbxproj.add(object: $0) }
        try XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
            .write(path: Path(projectURL.path))
    }
}
