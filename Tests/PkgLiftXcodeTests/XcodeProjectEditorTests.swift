import Foundation
import PathKit
import XCTest
import XcodeProj
import PkgLiftCore
@testable import PkgLiftXcode

final class XcodeProjectEditorTests: XCTestCase {
    func testEquivalentRepositoryURLsDoNotDuplicatePackageOrProduct() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let editor = XcodeProjectEditor()

        try editor.addSwiftPMPackage(
            repositoryURL: "https://github.com/Alamofire/Alamofire.git/",
            requirement: .exact("5.0.0"),
            to: fixture.project.path
        )
        try editor.addSwiftPMPackage(
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            requirement: .exact("5.0.0"),
            to: fixture.project.path
        )
        try editor.linkSwiftPMProduct(
            productName: "Alamofire",
            toTarget: "App",
            repositoryURL: "https://github.com/Alamofire/Alamofire.git",
            in: fixture.project.path
        )
        try editor.linkSwiftPMProduct(
            productName: "Alamofire",
            toTarget: "App",
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            in: fixture.project.path
        )

        let project = try XcodeProj(pathString: fixture.project.path)
        let rootProject = try XCTUnwrap(try project.pbxproj.rootProject())
        let target = try XCTUnwrap(project.pbxproj.nativeTargets.first { $0.name == "App" })
        let frameworks = try XCTUnwrap(try target.frameworksBuildPhase())
        XCTAssertEqual(rootProject.remotePackages.count, 1)
        XCTAssertEqual(target.packageProductDependencies?.count, 1)
        XCTAssertEqual(frameworks.files?.count, 1)
    }

    func testMissingTargetFailsWithoutChangingProject() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let editor = XcodeProjectEditor()
        try editor.addSwiftPMPackage(
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            requirement: .exact("5.0.0"),
            to: fixture.project.path
        )
        let projectFile = fixture.project.appendingPathComponent("project.pbxproj")
        let before = try Data(contentsOf: projectFile)

        XCTAssertThrowsError(try editor.linkSwiftPMProduct(
            productName: "Alamofire",
            toTarget: "Missing",
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            in: fixture.project.path
        )) { error in
            guard let editorError = error as? XcodeProjectEditorError,
                  case .targetNotFound(let target) = editorError else {
                return XCTFail("Expected targetNotFound, got \(error)")
            }
            XCTAssertEqual(target, "Missing")
        }
        XCTAssertEqual(try Data(contentsOf: projectFile), before)
    }

    func testExistingPackageWithDifferentRequirementIsRefusedWithoutMutation() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let editor = XcodeProjectEditor()
        try editor.addSwiftPMPackage(
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            requirement: .exact("5.0.0"),
            to: fixture.project.path
        )
        let projectFile = fixture.project.appendingPathComponent("project.pbxproj")
        let before = try Data(contentsOf: projectFile)

        XCTAssertThrowsError(try editor.addSwiftPMPackage(
            repositoryURL: "https://github.com/Alamofire/Alamofire.git",
            requirement: .from("5.0.0"),
            to: fixture.project.path
        )) { error in
            guard let editorError = error as? XcodeProjectEditorError,
                  case .packageRequirementConflict = editorError else {
                return XCTFail("Expected packageRequirementConflict, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: projectFile), before)
    }

    func testCaseSensitiveRepositoryPathsAreNotCollapsed() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let editor = XcodeProjectEditor()
        try editor.addSwiftPMPackage(
            repositoryURL: "https://example.com/Owner/Repository",
            requirement: .exact("1.0.0"),
            to: fixture.project.path
        )
        try editor.addSwiftPMPackage(
            repositoryURL: "https://example.com/owner/repository",
            requirement: .exact("1.0.0"),
            to: fixture.project.path
        )

        let project = try XcodeProj(pathString: fixture.project.path)
        let rootProject = try XCTUnwrap(try project.pbxproj.rootProject())
        XCTAssertEqual(rootProject.remotePackages.count, 2)
    }

    func testMalformedProjectProducesTypedError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftXcodeMalformed-\(UUID().uuidString)")
        let project = root.appendingPathComponent("Broken.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "not a pbx project".write(
            to: project.appendingPathComponent("project.pbxproj"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try XcodeProjectEditor().addSwiftPMPackage(
            repositoryURL: "https://github.com/example/package",
            requirement: .exact("1.0.0"),
            to: project.path
        )) { error in
            guard let editorError = error as? XcodeProjectEditorError,
                  case .invalidProject(let path) = editorError else {
                return XCTFail("Expected invalidProject, got \(error)")
            }
            XCTAssertEqual(path, project.path)
        }
    }

    private func makeProjectFixture() throws -> (root: URL, project: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftXcode-\(UUID().uuidString)")
        let projectURL = root.appendingPathComponent("App.xcodeproj")
        let mainGroup = PBXGroup(children: [], sourceTree: .group, name: "Main")
        let projectConfigurations = XCConfigurationList()
        let targetConfigurations = XCConfigurationList()
        let frameworks = PBXFrameworksBuildPhase(files: [])
        let target = PBXNativeTarget(
            name: "App",
            buildConfigurationList: targetConfigurations,
            buildPhases: [frameworks],
            productName: "App.app",
            productType: .application
        )
        let rootProject = PBXProject(
            name: "App",
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
        let xcodeproj = XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
        try xcodeproj.write(path: Path(projectURL.path))
        return (root, projectURL)
    }
}
