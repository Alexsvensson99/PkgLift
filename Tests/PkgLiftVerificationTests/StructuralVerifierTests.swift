import Foundation
import PathKit
import XCTest
import XcodeProj
import PkgLiftCore
import PkgLiftXcode
@testable import PkgLiftVerification

final class StructuralVerifierTests: XCTestCase {
    func testVerifiesExactPackageProductTargetAndIgnoresCommentedPod() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let editor = XcodeProjectEditor()
        try editor.addSwiftPMPackage(
            repositoryURL: "https://github.com/Alamofire/Alamofire.git",
            requirement: .exact("5.0.0"),
            to: fixture.project.path
        )
        try editor.linkSwiftPMProduct(
            productName: "Alamofire",
            toTarget: "App",
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            in: fixture.project.path
        )
        let podfile = fixture.root.appendingPathComponent("Podfile")
        try "# pod 'Alamofire' was migrated\ntarget 'App' do\nend".write(
            to: podfile,
            atomically: true,
            encoding: .utf8
        )

        let result = StructuralVerifier().verify(
            projectPath: fixture.project.path,
            migratedPods: ["Alamofire"],
            expectedPackages: ["https://github.com/Alamofire/Alamofire"],
            expectedProducts: [
                .init(
                    repositoryURL: "https://github.com/Alamofire/Alamofire",
                    productName: "Alamofire",
                    targetName: "App"
                )
            ],
            podfilePath: podfile.path
        )

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.checks.allSatisfy(\.passed))
    }

    func testWrongProductTargetFailsVerification() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let editor = XcodeProjectEditor()
        try editor.addSwiftPMPackage(
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            requirement: .exact("5.0.0"),
            to: fixture.project.path
        )
        try editor.linkSwiftPMProduct(
            productName: "Alamofire",
            toTarget: "App",
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            in: fixture.project.path
        )

        let result = StructuralVerifier().verify(
            projectPath: fixture.project.path,
            expectedProducts: [
                .init(
                    repositoryURL: "https://github.com/Alamofire/Alamofire",
                    productName: "Alamofire",
                    targetName: "Widget"
                )
            ]
        )

        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.failedChecks.contains { $0.name.contains("product_Alamofire_Widget") })
    }

    private func makeProjectFixture() throws -> (root: URL, project: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftVerification-\(UUID().uuidString)")
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
        try XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
            .write(path: Path(projectURL.path))
        return (root, projectURL)
    }
}
