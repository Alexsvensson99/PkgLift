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

    func testLinkingProductToAppPreservesSiblingTargetAndExistingProjectReferences() throws {
        let fixture = try makeMultiTargetProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let beforeProject = try XcodeProj(pathString: fixture.project.path)
        let beforeRoot = try XCTUnwrap(try beforeProject.pbxproj.rootProject())
        let beforeApp = try XCTUnwrap(
            beforeProject.pbxproj.nativeTargets.first { $0.name == "App" }
        )
        let beforeSibling = try XCTUnwrap(
            beforeProject.pbxproj.nativeTargets.first { $0.name == "AppTests" }
        )
        let siblingStateBefore = try targetState(beforeSibling)
        let projectReferencesBefore = projectReferenceState(beforeRoot)
        XCTAssertEqual(siblingStateBefore.productReference?.path, "AppTests.xctest")
        XCTAssertEqual(siblingStateBefore.nonFrameworkPhases.count, 1)
        XCTAssertEqual(siblingStateBefore.nonFrameworkPhases.first?.type, "PBXSourcesBuildPhase")
        XCTAssertEqual(siblingStateBefore.nonFrameworkPhases.first?.files.first?.fileName, "AppTests.swift")
        XCTAssertEqual(siblingStateBefore.dependencies.count, 1)
        XCTAssertEqual(siblingStateBefore.dependencies.first?.targetUUID, beforeApp.uuid)
        XCTAssertEqual(siblingStateBefore.dependencies.first?.proxy?.containerPortalUUID, beforeRoot.uuid)
        XCTAssertEqual(siblingStateBefore.dependencies.first?.proxy?.remoteGlobalID, beforeApp.uuid)

        try XcodeProjectEditor().linkSwiftPMProduct(
            productName: "Alamofire",
            toTarget: "App",
            repositoryURL: "https://github.com/Alamofire/Alamofire.git",
            in: fixture.project.path
        )

        let afterProject = try XcodeProj(pathString: fixture.project.path)
        let afterRoot = try XCTUnwrap(try afterProject.pbxproj.rootProject())
        let app = try XCTUnwrap(afterProject.pbxproj.nativeTargets.first { $0.name == "App" })
        let sibling = try XCTUnwrap(
            afterProject.pbxproj.nativeTargets.first { $0.name == "AppTests" }
        )
        let appFrameworks = try XCTUnwrap(try app.frameworksBuildPhase())
        let siblingFrameworks = try XCTUnwrap(try sibling.frameworksBuildPhase())

        let appDependencies = app.packageProductDependencies ?? []
        XCTAssertEqual(appDependencies.filter { $0.productName == "Alamofire" }.count, 1)
        XCTAssertEqual(appFrameworks.files?.filter { $0.product?.productName == "Alamofire" }.count, 1)
        XCTAssertEqual(
            appDependencies.first { $0.productName == "Alamofire" }?.package?.repositoryURL,
            "https://github.com/Alamofire/Alamofire"
        )

        XCTAssertEqual(siblingStateBefore, try targetState(sibling))
        XCTAssertEqual(sibling.packageProductDependencies?.filter { $0.productName == "Alamofire" }.count, 0)
        XCTAssertEqual(siblingFrameworks.files?.filter { $0.product?.productName == "Alamofire" }.count, 0)
        XCTAssertEqual(projectReferencesBefore, projectReferenceState(afterRoot))
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

    func testDuplicateExistingPackagesWithAnyDifferentOrUnknownRequirementAreRefusedWithoutMutation() throws {
        let requirementOrders: [[XCRemoteSwiftPackageReference.VersionRequirement?]] = [
            [.exact("5.0.0"), .branch("develop")],
            [.branch("develop"), .exact("5.0.0")],
            [.exact("5.0.0"), nil],
            [nil, .exact("5.0.0")],
        ]

        for requirements in requirementOrders {
            let fixture = try makeProjectFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            try addRawPackages(
                repositoryURL: "https://github.com/Alamofire/Alamofire.git/",
                requirements: requirements,
                to: fixture.project
            )
            let projectFile = fixture.project.appendingPathComponent("project.pbxproj")
            let before = try Data(contentsOf: projectFile)

            XCTAssertThrowsError(try XcodeProjectEditor().addSwiftPMPackage(
                repositoryURL: "https://github.com/Alamofire/Alamofire",
                requirement: .exact("5.0.0"),
                to: fixture.project.path
            )) { error in
                guard let editorError = error as? XcodeProjectEditorError,
                      case .packageRequirementConflict = editorError else {
                    return XCTFail("Expected packageRequirementConflict, got \(error)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: projectFile), before)
        }
    }

    func testDuplicateExistingPackagesWithEqualRequirementsRemainAcceptedWithoutMutation() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try addRawPackages(
            repositoryURL: "https://github.com/Alamofire/Alamofire.git/",
            requirements: [.exact("5.0.0"), .exact("5.0.0")],
            to: fixture.project
        )
        let projectFile = fixture.project.appendingPathComponent("project.pbxproj")
        let before = try Data(contentsOf: projectFile)

        XCTAssertNoThrow(try XcodeProjectEditor().addSwiftPMPackage(
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            requirement: .exact("5.0.0"),
            to: fixture.project.path
        ))
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

    private func makeMultiTargetProjectFixture() throws -> (root: URL, project: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftXcodeMultiTarget-\(UUID().uuidString)")
        let projectURL = root.appendingPathComponent("App.xcodeproj")

        let alamofirePackage = XCRemoteSwiftPackageReference(
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            versionRequirement: .exact("5.10.2")
        )
        let snapshotPackage = XCRemoteSwiftPackageReference(
            repositoryURL: "https://github.com/pointfreeco/swift-snapshot-testing",
            versionRequirement: .upToNextMajorVersion("1.18.0")
        )
        let snapshotProduct = XCSwiftPackageProductDependency(
            productName: "SnapshotTesting",
            package: snapshotPackage
        )
        let snapshotBuildFile = PBXBuildFile(
            product: snapshotProduct,
            settings: ["ATTRIBUTES": ["Weak"]],
            platformFilter: "ios"
        )
        let xctestReference = PBXFileReference(
            sourceTree: .sdkRoot,
            lastKnownFileType: "wrapper.framework",
            path: "XCTest.framework"
        )
        let xctestBuildFile = PBXBuildFile(file: xctestReference)
        let testsSourceReference = PBXFileReference(
            sourceTree: .group,
            lastKnownFileType: "sourcecode.swift",
            path: "AppTests.swift"
        )
        let testsSourceBuildFile = PBXBuildFile(
            file: testsSourceReference,
            settings: ["COMPILER_FLAGS": "-DAPP_TESTS"],
            platformFilter: "ios"
        )

        let projectDebug = XCBuildConfiguration(
            name: "Debug",
            buildSettings: ["SWIFT_VERSION": "6.0"]
        )
        let appDebug = XCBuildConfiguration(
            name: "Debug",
            buildSettings: ["PRODUCT_BUNDLE_IDENTIFIER": "com.example.App"]
        )
        let testsDebug = XCBuildConfiguration(
            name: "Debug",
            buildSettings: [
                "PRODUCT_BUNDLE_IDENTIFIER": "com.example.AppTests",
                "SWIFT_VERSION": "6.0",
                "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App",
            ]
        )
        let projectConfigurations = XCConfigurationList(
            buildConfigurations: [projectDebug],
            defaultConfigurationName: "Debug"
        )
        let appConfigurations = XCConfigurationList(
            buildConfigurations: [appDebug],
            defaultConfigurationName: "Debug"
        )
        let testsConfigurations = XCConfigurationList(
            buildConfigurations: [testsDebug],
            defaultConfigurationName: "Debug"
        )
        let appFrameworks = PBXFrameworksBuildPhase(files: [])
        let testsFrameworks = PBXFrameworksBuildPhase(
            files: [snapshotBuildFile, xctestBuildFile]
        )
        let testsSources = PBXSourcesBuildPhase(files: [testsSourceBuildFile])
        let appProductReference = PBXFileReference(
            sourceTree: .buildProductsDir,
            explicitFileType: "wrapper.application",
            path: "App.app"
        )
        let testsProductReference = PBXFileReference(
            sourceTree: .buildProductsDir,
            explicitFileType: "wrapper.cfbundle",
            path: "AppTests.xctest"
        )
        let appTarget = PBXNativeTarget(
            name: "App",
            buildConfigurationList: appConfigurations,
            buildPhases: [appFrameworks],
            productName: "App.app",
            product: appProductReference,
            productType: .application
        )
        let testsTarget = PBXNativeTarget(
            name: "AppTests",
            buildConfigurationList: testsConfigurations,
            buildPhases: [testsSources, testsFrameworks],
            productName: "AppTests.xctest",
            product: testsProductReference,
            productType: .unitTestBundle
        )
        testsTarget.packageProductDependencies = [snapshotProduct]

        let mainGroup = PBXGroup(
            children: [xctestReference, testsSourceReference],
            sourceTree: .group,
            name: "Main"
        )
        let productsGroup = PBXGroup(
            children: [appProductReference, testsProductReference],
            sourceTree: .group,
            name: "Products"
        )
        let rootProject = PBXProject(
            name: "App",
            buildConfigurationList: projectConfigurations,
            compatibilityVersion: "Xcode 15.0",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup,
            productsGroup: productsGroup,
            targets: [appTarget, testsTarget],
            packages: [alamofirePackage, snapshotPackage]
        )
        let appTargetProxy = PBXContainerItemProxy(
            containerPortal: .project(rootProject),
            remoteGlobalID: .object(appTarget),
            proxyType: .nativeTarget,
            remoteInfo: "App"
        )
        let appTargetDependency = PBXTargetDependency(
            name: "App",
            platformFilter: "ios",
            target: appTarget,
            targetProxy: appTargetProxy
        )
        testsTarget.dependencies = [appTargetDependency]
        let pbxproj = PBXProj(
            rootObject: rootProject,
            objectVersion: 56,
            archiveVersion: 1,
            classes: [:],
            objects: []
        )
        [
            alamofirePackage,
            snapshotPackage,
            snapshotProduct,
            snapshotBuildFile,
            xctestReference,
            xctestBuildFile,
            testsSourceReference,
            testsSourceBuildFile,
            projectDebug,
            appDebug,
            testsDebug,
            projectConfigurations,
            appConfigurations,
            testsConfigurations,
            appFrameworks,
            testsFrameworks,
            testsSources,
            appProductReference,
            testsProductReference,
            appTarget,
            testsTarget,
            appTargetProxy,
            appTargetDependency,
            mainGroup,
            productsGroup,
            rootProject,
        ].forEach { pbxproj.add(object: $0) }
        try XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
            .write(path: Path(projectURL.path))
        return (root, projectURL)
    }

    private func targetState(_ target: PBXNativeTarget) throws -> TargetState {
        let frameworks = try XCTUnwrap(try target.frameworksBuildPhase())
        let configurationList = try XCTUnwrap(target.buildConfigurationList)
        return TargetState(
            targetUUID: target.uuid,
            configurationListUUID: configurationList.uuid,
            buildPhaseUUIDs: target.buildPhases.map(\.uuid),
            frameworkPhaseUUID: frameworks.uuid,
            productReference: target.product.map(productReferenceState),
            products: (target.packageProductDependencies ?? []).map(productState),
            frameworkFiles: (frameworks.files ?? []).map(buildFileState),
            nonFrameworkPhases: target.buildPhases.compactMap { phase in
                guard !(phase is PBXFrameworksBuildPhase) else { return nil }
                return BuildPhaseState(
                    uuid: phase.uuid,
                    type: String(describing: type(of: phase)),
                    buildActionMask: phase.buildActionMask,
                    runOnlyForDeploymentPostprocessing: phase.runOnlyForDeploymentPostprocessing,
                    inputFileListPaths: phase.inputFileListPaths,
                    outputFileListPaths: phase.outputFileListPaths,
                    files: (phase.files ?? []).map(buildFileState)
                )
            },
            dependencies: target.dependencies.map(dependencyState),
            configurations: configurationList.buildConfigurations.map { configuration in
                BuildConfigurationState(
                    uuid: configuration.uuid,
                    name: configuration.name,
                    buildSettings: configuration.buildSettings
                )
            }
        )
    }

    private func productReferenceState(_ product: PBXFileReference) -> ProductReferenceState {
        ProductReferenceState(
            uuid: product.uuid,
            name: product.name,
            path: product.path,
            sourceTree: product.sourceTree.map { String(describing: $0) },
            explicitFileType: product.explicitFileType,
            lastKnownFileType: product.lastKnownFileType
        )
    }

    private func buildFileState(_ buildFile: PBXBuildFile) -> BuildFileState {
        BuildFileState(
            uuid: buildFile.uuid,
            fileUUID: buildFile.file?.uuid,
            fileName: buildFile.file?.name ?? buildFile.file?.path,
            product: buildFile.product.map(productState),
            settings: buildFile.settings,
            platformFilter: buildFile.platformFilter,
            platformFilters: buildFile.platformFilters
        )
    }

    private func dependencyState(_ dependency: PBXTargetDependency) -> TargetDependencyState {
        TargetDependencyState(
            uuid: dependency.uuid,
            name: dependency.name,
            targetUUID: dependency.target?.uuid,
            targetName: dependency.target?.name,
            proxy: dependency.targetProxy.map(proxyState),
            product: dependency.product.map(productState),
            platformFilter: dependency.platformFilter,
            platformFilters: dependency.platformFilters
        )
    }

    private func proxyState(_ proxy: PBXContainerItemProxy) -> ContainerProxyState {
        let portal: (type: String, uuid: String?)
        switch proxy.containerPortal {
        case .project(let project):
            portal = ("project", project.uuid)
        case .fileReference(let file):
            portal = ("fileReference", file.uuid)
        case .unknownObject(let object):
            portal = ("unknownObject", object?.uuid)
        }

        let remoteGlobalID: String?
        switch proxy.remoteGlobalID {
        case .object(let object):
            remoteGlobalID = object.uuid
        case .string(let value):
            remoteGlobalID = value
        case nil:
            remoteGlobalID = nil
        }

        return ContainerProxyState(
            uuid: proxy.uuid,
            containerPortalType: portal.type,
            containerPortalUUID: portal.uuid,
            proxyType: proxy.proxyType?.rawValue,
            remoteGlobalID: remoteGlobalID,
            remoteInfo: proxy.remoteInfo
        )
    }

    private func productState(_ product: XCSwiftPackageProductDependency) -> ProductState {
        ProductState(
            uuid: product.uuid,
            productName: product.productName,
            packageUUID: product.package?.uuid,
            repositoryURL: product.package?.repositoryURL
        )
    }

    private func projectReferenceState(_ project: PBXProject) -> ProjectReferenceState {
        ProjectReferenceState(
            projectUUID: project.uuid,
            mainGroupUUID: project.mainGroup.uuid,
            productsGroupUUID: project.productsGroup?.uuid,
            configurationListUUID: project.buildConfigurationList.uuid,
            targetUUIDs: project.targets.map(\.uuid),
            packages: project.remotePackages.map { package in
                PackageReferenceState(
                    uuid: package.uuid,
                    repositoryURL: package.repositoryURL,
                    versionRequirement: package.versionRequirement
                )
            }
        )
    }

    private struct TargetState: Equatable {
        let targetUUID: String
        let configurationListUUID: String
        let buildPhaseUUIDs: [String]
        let frameworkPhaseUUID: String
        let productReference: ProductReferenceState?
        let products: [ProductState]
        let frameworkFiles: [BuildFileState]
        let nonFrameworkPhases: [BuildPhaseState]
        let dependencies: [TargetDependencyState]
        let configurations: [BuildConfigurationState]
    }

    private struct ProductState: Equatable {
        let uuid: String
        let productName: String
        let packageUUID: String?
        let repositoryURL: String?
    }

    private struct ProductReferenceState: Equatable {
        let uuid: String
        let name: String?
        let path: String?
        let sourceTree: String?
        let explicitFileType: String?
        let lastKnownFileType: String?
    }

    private struct BuildFileState: Equatable {
        let uuid: String
        let fileUUID: String?
        let fileName: String?
        let product: ProductState?
        let settings: [String: BuildFileSetting]?
        let platformFilter: String?
        let platformFilters: [String]?
    }

    private struct BuildPhaseState: Equatable {
        let uuid: String
        let type: String
        let buildActionMask: UInt
        let runOnlyForDeploymentPostprocessing: Bool
        let inputFileListPaths: [String]?
        let outputFileListPaths: [String]?
        let files: [BuildFileState]
    }

    private struct TargetDependencyState: Equatable {
        let uuid: String
        let name: String?
        let targetUUID: String?
        let targetName: String?
        let proxy: ContainerProxyState?
        let product: ProductState?
        let platformFilter: String?
        let platformFilters: [String]?
    }

    private struct ContainerProxyState: Equatable {
        let uuid: String
        let containerPortalType: String
        let containerPortalUUID: String?
        let proxyType: UInt?
        let remoteGlobalID: String?
        let remoteInfo: String?
    }

    private struct BuildConfigurationState: Equatable {
        let uuid: String
        let name: String
        let buildSettings: BuildSettings
    }

    private struct ProjectReferenceState: Equatable {
        let projectUUID: String
        let mainGroupUUID: String
        let productsGroupUUID: String?
        let configurationListUUID: String
        let targetUUIDs: [String]
        let packages: [PackageReferenceState]
    }

    private struct PackageReferenceState: Equatable {
        let uuid: String
        let repositoryURL: String?
        let versionRequirement: XCRemoteSwiftPackageReference.VersionRequirement?
    }

    private func addRawPackages(
        repositoryURL: String,
        requirements: [XCRemoteSwiftPackageReference.VersionRequirement?],
        to projectURL: URL
    ) throws {
        let xcodeproj = try XcodeProj(pathString: projectURL.path)
        let rootProject = try XCTUnwrap(try xcodeproj.pbxproj.rootProject())
        for requirement in requirements {
            let package = XCRemoteSwiftPackageReference(
                repositoryURL: repositoryURL,
                versionRequirement: requirement
            )
            xcodeproj.pbxproj.add(object: package)
            rootProject.remotePackages.append(package)
        }
        try xcodeproj.write(pathString: projectURL.path, override: true)
    }
}
