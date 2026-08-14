import Foundation
import PathKit
import XCTest
import XcodeProj
import PkgLiftCore
import PkgLiftXcode
@testable import PkgLiftCLI

final class CommandContextMigrationTests: XCTestCase {
    func testPlanDryRunApplyAndVerifyEndToEndInNonGitProject() async throws {
        let fixture = try makeFixture(
            podfile: "target 'App' do\n  pod 'Alamofire'\nend\n",
            lockfile: "PODS:\n  - Alamofire (5.0.0)\nDEPENDENCIES:\n  - Alamofire\n",
            targetNames: ["App"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let arguments = ["--path", fixture.root.path, "--project", fixture.project.path]

        var planCommand = try PlanCommand.parse(arguments)
        try await planCommand.run()
        let planURL = fixture.root.appendingPathComponent(".pkglift/plan.json")
        let planData = try Data(contentsOf: planURL)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: planData))

        let podfile = fixture.root.appendingPathComponent("Podfile")
        let beforeDryRun = try String(contentsOf: podfile)
        var dryRun = try MigrateCommand.parse(arguments)
        try await dryRun.run()
        XCTAssertEqual(try String(contentsOf: podfile), beforeDryRun)

        var apply = try MigrateCommand.parse(arguments + ["--apply"])
        try await apply.run()
        XCTAssertFalse(try String(contentsOf: podfile).contains("pod 'Alamofire'"))
        let analysis = try XcodeProjectAnalyzer().analyzeProject(at: fixture.project.path)
        XCTAssertEqual(analysis.swiftPMState.packages.count, 1)
        XCTAssertEqual(analysis.swiftPMState.packages[0].linkedProducts, [
            LinkedProduct(productName: "Alamofire", targetName: "App")
        ])

        var verify = try VerifyCommand.parse(arguments)
        try await verify.run()
    }

    func testDirtyGitProjectRefusesBeforeMutationAndAllowDirtyOverrides() async throws {
        let fixture = try makeFixture(
            podfile: "target 'App' do\n  pod 'Alamofire'\nend\n",
            lockfile: "PODS:\n  - Alamofire (5.0.0)\nDEPENDENCIES:\n  - Alamofire\n",
            targetNames: ["App"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let arguments = ["--path", fixture.root.path, "--project", fixture.project.path]
        var planCommand = try PlanCommand.parse(arguments)
        try await planCommand.run()
        try runGit(["init", "--quiet"], in: fixture.root)
        try runGit(["config", "user.email", "pkglift-tests@example.invalid"], in: fixture.root)
        try runGit(["config", "user.name", "PkgLift Tests"], in: fixture.root)
        try runGit(["add", "."], in: fixture.root)
        try runGit(["commit", "--quiet", "-m", "fixture"], in: fixture.root)
        let podfile = fixture.root.appendingPathComponent("Podfile")
        try "\n# local change".append(to: podfile)
        let beforeRefusal = try String(contentsOf: podfile)

        var refused = try MigrateCommand.parse(arguments + ["--apply"])
        do {
            try await refused.run()
            XCTFail("Expected dirty repository refusal")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("uncommitted"))
        }
        XCTAssertEqual(try String(contentsOf: podfile), beforeRefusal)

        var allowed = try MigrateCommand.parse(arguments + ["--apply", "--allow-dirty"])
        try await allowed.run()
        XCTAssertFalse(try String(contentsOf: podfile).contains("pod 'Alamofire'"))
    }

    func testLockfileVersionAndPodfileTargetReachExecutableAutoPlan() async throws {
        let fixture = try makeFixture(
            podfile: "target 'App' do\n  pod 'Alamofire'\nend\n",
            lockfile: """
            PODS:
              - Alamofire (5.0.0)
            DEPENDENCIES:
              - Alamofire
            """,
            targetNames: ["App"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let options = try CommonOptions.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
        ])

        let context = try await CommandContext.load(from: options)
        let plan = context.buildMigrationPlan()
        let entry = try XCTUnwrap(plan.entries.first)

        XCTAssertEqual(entry.currentVersion, "5.0.0")
        XCTAssertEqual(entry.targetName, "App")
        XCTAssertEqual(entry.classification, .auto)
        XCTAssertEqual(entry.actions, [
            .removePod(name: "Alamofire"),
            .addSwiftPackage(
                repositoryURL: "https://github.com/Alamofire/Alamofire",
                requirement: .exact("5.0.0")
            ),
            .linkProduct(
                repositoryURL: "https://github.com/Alamofire/Alamofire",
                productName: "Alamofire",
                targetName: "App"
            ),
        ])
    }

    func testNoLockfileVersionIsReviewAndNeverGetsFakeRequirement() async throws {
        let fixture = try makeFixture(
            podfile: "target 'App' do\n  pod 'Alamofire'\nend\n",
            lockfile: nil,
            targetNames: ["App"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let options = try CommonOptions.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
        ])

        let context = try await CommandContext.load(from: options)
        let entry = try XCTUnwrap(context.buildMigrationPlan().entries.first)

        XCTAssertEqual(entry.classification, .review)
        XCTAssertNil(entry.packageCandidate?.versionRequirement)
        XCTAssertFalse(String(describing: entry.actions).contains("0.0.0"))
    }

    func testDependencyDeclaredForTwoTargetsIsReview() async throws {
        let fixture = try makeFixture(
            podfile: """
            target 'App' do
              pod 'Alamofire'
            end
            target 'Widget' do
              pod 'Alamofire'
            end
            """,
            lockfile: """
            PODS:
              - Alamofire (5.0.0)
            DEPENDENCIES:
              - Alamofire
            """,
            targetNames: ["App", "Widget"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let options = try CommonOptions.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
        ])

        let context = try await CommandContext.load(from: options)
        let entry = try XCTUnwrap(context.buildMigrationPlan().entries.first)

        XCTAssertEqual(entry.classification, .review)
        XCTAssertNil(entry.targetName)
        XCTAssertFalse(entry.actions.contains { action in
            if case .addSwiftPackage = action { return true }
            return false
        })
    }

    func testBasePodDoesNotInheritArbitrarySubspecMapping() async throws {
        let fixture = try makeFixture(
            podfile: "target 'App' do\n  pod 'Firebase'\nend\n",
            lockfile: "PODS:\n  - Firebase (12.0.0)\nDEPENDENCIES:\n  - Firebase\n",
            targetNames: ["App"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let options = try CommonOptions.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
        ])

        let context = try await CommandContext.load(from: options)
        let entry = try XCTUnwrap(context.buildMigrationPlan().entries.first)

        XCTAssertEqual(entry.classification, .unknown)
        XCTAssertNil(entry.packageCandidate)
        XCTAssertFalse(entry.actions.contains { action in
            if case .addSwiftPackage = action { return true }
            return false
        })
    }

    func testTransitiveSubspecDoesNotInheritBasePodMapping() async throws {
        let fixture = try makeFixture(
            podfile: "target 'App' do\n  pod 'SDWebImage'\nend\n",
            lockfile: """
            PODS:
              - SDWebImage (5.18.1):
                - SDWebImage/Core (= 5.18.1)
              - SDWebImage/Core (5.18.1)
            DEPENDENCIES:
              - SDWebImage
            """,
            targetNames: ["App"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let options = try CommonOptions.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
        ])

        let context = try await CommandContext.load(from: options)
        let analysis = context.buildProjectAnalysis()
        let base = try XCTUnwrap(analysis.candidates.first { $0.pod.name == "SDWebImage" })
        let core = try XCTUnwrap(analysis.candidates.first { $0.pod.name == "SDWebImage/Core" })

        XCTAssertEqual(base.classification, .auto)
        XCTAssertTrue(base.pod.isDirect)
        XCTAssertEqual(core.classification, .unknown)
        XCTAssertFalse(core.pod.isDirect)
        XCTAssertNil(core.packageCandidate)

        let plan = context.buildMigrationPlan()
        XCTAssertEqual(plan.entries.map(\.podName), ["SDWebImage"])
    }

    func testDenyConfigurationPreventsAutoPlan() async throws {
        let fixture = try makeFixture(
            podfile: "target 'App' do\n  pod 'Alamofire'\nend\n",
            lockfile: "PODS:\n  - Alamofire (5.0.0)\nDEPENDENCIES:\n  - Alamofire\n",
            targetNames: ["App"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try "schemaVersion: 1\nmigration:\n  deny: [Alamofire]\n".write(
            to: fixture.root.appendingPathComponent(".pkglift.yml"),
            atomically: true,
            encoding: .utf8
        )
        let options = try CommonOptions.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
        ])

        let context = try await CommandContext.load(from: options)
        let entry = try XCTUnwrap(context.buildMigrationPlan().entries.first)

        XCTAssertEqual(entry.classification, .blocked)
        XCTAssertFalse(entry.actions.contains { action in
            if case .addSwiftPackage = action { return true }
            return false
        })
    }

    func testInvalidConfigurationIsNotSilentlyIgnored() async throws {
        let fixture = try makeFixture(
            podfile: "target 'App' do\n  pod 'Alamofire'\nend\n",
            lockfile: nil,
            targetNames: ["App"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try "schemaVersion: 99\n".write(
            to: fixture.root.appendingPathComponent(".pkglift.yml"),
            atomically: true,
            encoding: .utf8
        )
        let options = try CommonOptions.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
        ])

        do {
            _ = try await CommandContext.load(from: options)
            XCTFail("Expected invalid configuration to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("schema version"))
        }
    }

    private func makeFixture(
        podfile: String,
        lockfile: String?,
        targetNames: [String]
    ) throws -> (root: URL, project: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftCLI-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try podfile.write(to: root.appendingPathComponent("Podfile"), atomically: true, encoding: .utf8)
        if let lockfile {
            try lockfile.write(
                to: root.appendingPathComponent("Podfile.lock"),
                atomically: true,
                encoding: .utf8
            )
        }

        let projectURL = root.appendingPathComponent("App.xcodeproj")
        let mainGroup = PBXGroup(children: [], sourceTree: .group, name: "Main")
        let projectConfigurations = XCConfigurationList()
        var objects: [PBXObject] = [mainGroup, projectConfigurations]
        let targets: [PBXNativeTarget] = targetNames.map { name in
            let configurations = XCConfigurationList()
            let frameworks = PBXFrameworksBuildPhase(files: [])
            let target = PBXNativeTarget(
                name: name,
                buildConfigurationList: configurations,
                buildPhases: [frameworks],
                productName: "\(name).app",
                productType: .application
            )
            objects.append(contentsOf: [configurations, frameworks, target])
            return target
        }
        let rootProject = PBXProject(
            name: "App",
            buildConfigurationList: projectConfigurations,
            compatibilityVersion: "Xcode 15.0",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup,
            targets: targets
        )
        objects.append(rootProject)
        let pbxproj = PBXProj(
            rootObject: rootProject,
            objectVersion: 56,
            archiveVersion: 1,
            classes: [:],
            objects: []
        )
        objects.forEach { pbxproj.add(object: $0) }
        try XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
            .write(path: Path(projectURL.path))
        return (root, projectURL)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        let stderr = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let detail = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            XCTFail("git failed: \(detail)")
        }
    }
}

private extension String {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(utf8))
    }
}
