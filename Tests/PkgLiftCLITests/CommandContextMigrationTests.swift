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

    func testApplyRefusesWhenSavedAutoPlanNoLongerMatchesCurrentPodfile() async throws {
        let fixture = try makeFixture(
            podfile: "target 'App' do\n  pod 'Alamofire'\nend\n",
            lockfile: "PODS:\n  - Alamofire (5.0.0)\nDEPENDENCIES:\n  - Alamofire\n",
            targetNames: ["App"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let arguments = ["--path", fixture.root.path, "--project", fixture.project.path]
        var planCommand = try PlanCommand.parse(arguments)
        try await planCommand.run()

        let podfile = fixture.root.appendingPathComponent("Podfile")
        let changedPodfile = "target 'App' do\n  pod 'Alamofire' if ENV['USE_ALAMOFIRE']\nend\n"
        try changedPodfile.write(to: podfile, atomically: true, encoding: .utf8)

        var apply = try MigrateCommand.parse(arguments + ["--apply"])
        do {
            try await apply.run()
            XCTFail("Expected stale plan refusal")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("saved plan no longer matches"))
            XCTAssertTrue(error.localizedDescription.contains("Regenerate"))
        }

        XCTAssertEqual(try String(contentsOf: podfile), changedPodfile)
        let analysis = try XcodeProjectAnalyzer().analyzeProject(at: fixture.project.path)
        XCTAssertTrue(analysis.swiftPMState.packages.isEmpty)
    }

    func testApplyRefusesWhenSavedAutoTargetAttributionHasChanged() async throws {
        let fixture = try makeFixture(
            podfile: "target 'App' do\n  pod 'Alamofire'\nend\n",
            lockfile: "PODS:\n  - Alamofire (5.0.0)\nDEPENDENCIES:\n  - Alamofire\n",
            targetNames: ["App", "Widget"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let arguments = ["--path", fixture.root.path, "--project", fixture.project.path]
        var planCommand = try PlanCommand.parse(arguments)
        try await planCommand.run()

        let podfile = fixture.root.appendingPathComponent("Podfile")
        let changedPodfile = "target 'Widget' do\n  pod 'Alamofire'\nend\n"
        try changedPodfile.write(to: podfile, atomically: true, encoding: .utf8)

        var apply = try MigrateCommand.parse(arguments + ["--apply"])
        do {
            try await apply.run()
            XCTFail("Expected stale target-attribution refusal")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("saved plan no longer matches"))
        }

        XCTAssertEqual(try String(contentsOf: podfile), changedPodfile)
        let analysis = try XcodeProjectAnalyzer().analyzeProject(at: fixture.project.path)
        XCTAssertTrue(analysis.swiftPMState.packages.isEmpty)
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
        XCTAssertEqual(entry.packageCandidate?.supportedConsumerLanguages, [.swift])
        XCTAssertEqual(
            entry.targetSourceProfile,
            TargetSourceProfile(languages: [.swift], completeness: .complete)
        )
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

    func testMixedSwiftObjectiveCTargetIsAutoOnlyWithMatchingRegistryEvidence() async throws {
        let fixture = try makeFixture(
            podfile: "target 'App' do\n  pod 'SDWebImage'\nend\n",
            lockfile: "PODS:\n  - SDWebImage (5.18.1)\nDEPENDENCIES:\n  - SDWebImage\n",
            targetNames: ["App"],
            targetSourceFileTypes: [
                "App": ["sourcecode.swift", "sourcecode.c.objc"],
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let options = try CommonOptions.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
        ])

        let context = try await CommandContext.load(from: options)
        let entry = try XCTUnwrap(context.buildMigrationPlan().entries.first)

        XCTAssertEqual(entry.classification, .auto)
        XCTAssertEqual(entry.packageCandidate?.supportedConsumerLanguages, [.swift, .objectiveC])
        XCTAssertEqual(
            entry.targetSourceProfile,
            TargetSourceProfile(
                languages: [.swift, .objectiveC],
                completeness: .complete
            )
        )
    }

    func testApplyRefusesSavedAutoPlanWithLanguageEvidenceRemoved() async throws {
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
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: planURL)) as? [String: Any]
        )
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "targetSourceProfile")
        var package = try XCTUnwrap(entries[0]["packageCandidate"] as? [String: Any])
        package.removeValue(forKey: "supportedConsumerLanguages")
        entries[0]["packageCandidate"] = package
        object["entries"] = entries
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: planURL, options: .atomic)

        let podfileURL = fixture.root.appendingPathComponent("Podfile")
        let originalPodfile = try String(contentsOf: podfileURL)
        var apply = try MigrateCommand.parse(arguments + ["--apply"])
        do {
            try await apply.run()
            XCTFail("Expected language-evidence preflight refusal")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("consumer-language evidence"))
            XCTAssertTrue(error.localizedDescription.contains("Regenerate"))
        }

        XCTAssertEqual(try String(contentsOf: podfileURL), originalPodfile)
        let analysis = try XcodeProjectAnalyzer().analyzeProject(at: fixture.project.path)
        XCTAssertTrue(analysis.swiftPMState.packages.isEmpty)
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
        XCTAssertEqual(entry.targetAttribution?.status, .multiple)
        XCTAssertEqual(entry.targetAttribution?.targets, ["App", "Widget"])
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

    func testBarkLikeCountsOriginsTargetsAndReasonsAreConsistent() async throws {
        let fixture = try makeFixture(
            podfile: Self.barkLikePodfile,
            lockfile: Self.barkLikeLockfile,
            targetNames: [
                "WidgetExtension",
                "NotificationServiceExtension",
                "AppTests",
                "App",
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let options = try CommonOptions.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
        ])

        let context = try await CommandContext.load(from: options)
        let analysis = context.buildProjectAnalysis()
        let plan = context.buildMigrationPlan()

        let expectedCounts = DependencyCounts(
            literalPodfileDeclarationCount: 6,
            uniqueDirectDependencyCount: 4,
            uniqueLockfileDependencyCount: 5,
            planEntryCount: 4,
            analysisCandidateCount: 5
        )
        XCTAssertEqual(analysis.counts, expectedCounts)
        XCTAssertEqual(plan.counts, expectedCounts)
        XCTAssertEqual(analysis.cocoaPods.directDependencies.count, 6)
        XCTAssertEqual(analysis.candidates.count, 5)
        XCTAssertEqual(analysis.project.targets.map(\.name).sorted(), [
            "App",
            "AppTests",
            "NotificationServiceExtension",
            "WidgetExtension",
        ])
        XCTAssertEqual(plan.entries.count, 4)
        XCTAssertEqual(Set(plan.entries.map(\.podName)).count, 4)

        let literalKingfisherTargets = context.directDependencies
            .filter { $0.name == "Kingfisher" }
            .map(\.targets)
        XCTAssertEqual(literalKingfisherTargets, [
            ["App"],
            ["NotificationServiceExtension"],
            ["WidgetExtension"],
        ])

        let kingfisher = try XCTUnwrap(plan.entries.first { $0.podName == "Kingfisher" })
        XCTAssertEqual(kingfisher.targetAttribution?.status, .multiple)
        XCTAssertEqual(kingfisher.targetAttribution?.targets, [
            "App",
            "NotificationServiceExtension",
            "WidgetExtension",
        ])
        XCTAssertEqual(kingfisher.targetAttribution?.unresolvedDeclarationCount, 0)
        XCTAssertNil(kingfisher.targetName)
        XCTAssertEqual(kingfisher.declarations?.count, 3)
        XCTAssertEqual(kingfisher.declarations?.map(\.targetName), [
            "App",
            "NotificationServiceExtension",
            "WidgetExtension",
        ])
        XCTAssertTrue(kingfisher.reasons.contains("Podfile install hook detected"))
        XCTAssertTrue(kingfisher.reasons.contains("Dynamic Podfile logic detected"))
        XCTAssertTrue(kingfisher.reasons.contains("inherit! :search_paths detected"))
        XCTAssertTrue(kingfisher.reasons.contains { $0.contains("Multiple statically proven") })

        let moya = try XCTUnwrap(plan.entries.first { $0.podName == "Moya" })
        let moyaRx = try XCTUnwrap(plan.entries.first { $0.podName == "Moya/RxSwift" })
        XCTAssertEqual(moya.targetAttribution?.status, .exact)
        XCTAssertEqual(moya.targetName, "NotificationServiceExtension")
        XCTAssertNotNil(moya.packageCandidate)
        XCTAssertEqual(moyaRx.targetAttribution?.status, .exact)
        XCTAssertEqual(moyaRx.targetName, "App")
        XCTAssertNil(moyaRx.packageCandidate)
        XCTAssertEqual(moyaRx.classification, .unknown)

        let external = try XCTUnwrap(plan.entries.first { $0.podName == "ExternalKit" })
        XCTAssertEqual(external.classification, .blocked)
        XCTAssertEqual(external.targetAttribution?.status, .exact)
        XCTAssertEqual(external.targetName, "App")
        XCTAssertEqual(external.reasons.prefix(2), [
            "External source without mapping",
            "No registry mapping",
        ])
        XCTAssertEqual(plan.autoEntries.count, 0)

        XCTAssertEqual(
            try normalizedJSON(analysis),
            try normalizedJSON(context.buildProjectAnalysis())
        )
        XCTAssertEqual(
            try normalizedJSON(plan),
            try normalizedJSON(context.buildMigrationPlan())
        )
    }

    private func makeFixture(
        podfile: String,
        lockfile: String?,
        targetNames: [String],
        targetSourceFileTypes: [String: [String]] = [:]
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
        let projectConfigurations = XCConfigurationList()
        var objects: [PBXObject] = [projectConfigurations]
        var sourceReferences: [PBXFileReference] = []
        var targets: [PBXNativeTarget] = []
        for name in targetNames {
            let configurations = XCConfigurationList()
            let frameworks = PBXFrameworksBuildPhase(files: [])
            let references = (targetSourceFileTypes[name] ?? ["sourcecode.swift"])
                .enumerated()
                .map { index, fileType in
                    PBXFileReference(
                        sourceTree: .group,
                        lastKnownFileType: fileType,
                        path: "\(name)Source\(index)"
                    )
                }
            let sourceBuildFiles = references.map { PBXBuildFile(file: $0) }
            let sources = PBXSourcesBuildPhase(files: sourceBuildFiles)
            let target = PBXNativeTarget(
                name: name,
                buildConfigurationList: configurations,
                buildPhases: [sources, frameworks],
                productName: "\(name).app",
                productType: .application
            )
            sourceReferences.append(contentsOf: references)
            targets.append(target)
            objects.append(contentsOf: references)
            objects.append(contentsOf: sourceBuildFiles)
            objects.append(contentsOf: [configurations, sources, frameworks, target])
        }
        let mainGroup = PBXGroup(
            children: sourceReferences,
            sourceTree: .group,
            name: "Main"
        )
        objects.insert(mainGroup, at: 0)
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

    private func normalizedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(value)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "timestamp")
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    }

    private static let barkLikePodfile = """
    def pods
      pod 'Moya/RxSwift'
      pod 'Kingfisher'
      pod 'ExternalKit', :git => 'https://example.invalid/ExternalKit.git', :branch => 'main'
    end

    target 'App' do
      pods
      target 'AppTests' do
        inherit! :search_paths
      end
    end

    target 'NotificationServiceExtension' do
      pod 'Kingfisher'
      pod 'Moya'
    end

    target 'WidgetExtension' do
      pod 'Kingfisher'
    end

    post_install do |installer|
      installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
          config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
        end
      end
    end
    """

    private static let barkLikeLockfile = """
    PODS:
      - ExternalKit (1.0.0)
      - Kingfisher (8.6.1)
      - Moya (15.0.0):
        - Moya/Core (= 15.0.0)
      - Moya/Core (15.0.0)
      - Moya/RxSwift (15.0.0):
        - Moya/Core (= 15.0.0)
    DEPENDENCIES:
      - ExternalKit (from `https://example.invalid/ExternalKit.git`, branch `main`)
      - Kingfisher
      - Moya
      - Moya/RxSwift
    EXTERNAL SOURCES:
      ExternalKit:
        :branch: main
        :git: https://example.invalid/ExternalKit.git
    CHECKOUT OPTIONS:
      ExternalKit:
        :branch: main
        :git: https://example.invalid/ExternalKit.git
    """
}

private extension String {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(utf8))
    }
}
