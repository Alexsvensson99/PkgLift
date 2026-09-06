import ArgumentParser
import Darwin
import Dispatch
import Foundation
import PathKit
import XCTest
import XcodeProj
import PkgLiftMigration
@testable import PkgLiftCLI

final class MigrateInterruptionTests: XCTestCase {
    private static let helperRootEnvironment = "PKGLIFT_TEST_INTERRUPT_ROOT"
    private static let helperProjectEnvironment = "PKGLIFT_TEST_INTERRUPT_PROJECT"
    private static let helperStageEnvironment = "PKGLIFT_TEST_INTERRUPT_STAGE"
    private static let helperSignalEnvironment = "PKGLIFT_TEST_INTERRUPT_SIGNAL"

    func testSIGINTAfterPodfileWriteRollsBackAndPreservesBackup() async throws {
        try await assertInterruptedMigrationRollsBack(stage: .podfileWritten, signal: SIGINT)
    }

    func testSIGINTAfterPackageAddRollsBackAndPreservesBackup() async throws {
        try await assertInterruptedMigrationRollsBack(stage: .packageAdded(0), signal: SIGINT)
    }

    func testSIGTERMAfterPodfileWriteRollsBackAndPreservesBackup() async throws {
        try await assertInterruptedMigrationRollsBack(stage: .podfileWritten, signal: SIGTERM)
    }

    func testSIGTERMAfterPackageAddRollsBackAndPreservesBackup() async throws {
        try await assertInterruptedMigrationRollsBack(stage: .packageAdded(0), signal: SIGTERM)
    }

    func testSIGKILLLeavesRecoveryMarkerAndBackupThatRefusesAnotherApply() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await writePlan(for: fixture)

        let podfile = fixture.root.appendingPathComponent("Podfile")
        let nestedAuxiliary = fixture.project
            .appendingPathComponent("xcshareddata", isDirectory: true)
            .appendingPathComponent("PkgLiftFixture.xcconfig")
        try FileManager.default.createDirectory(
            at: nestedAuxiliary.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("ORIGINAL_NESTED_AUXILIARY\n".utf8).write(to: nestedAuxiliary)
        let originalPodfile = try Data(contentsOf: podfile)
        let originalProject = try regularFileContents(beneath: fixture.project)

        let terminationStatus = try runChildProcess(
            fixture: fixture,
            stage: .podfileWritten,
            signal: SIGKILL,
            expectsRegularExit: false
        )
        XCTAssertEqual(terminationStatus, SIGKILL)

        let stateDirectory = fixture.root.appendingPathComponent(".pkglift", isDirectory: true)
        let marker = stateDirectory.appendingPathComponent("migration-in-progress")
        let backup = stateDirectory.appendingPathComponent("backup", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Podfile")), originalPodfile)
        XCTAssertEqual(
            try regularFileContents(beneath: backup.appendingPathComponent("App.xcodeproj")),
            originalProject
        )

        var secondApply = try MigrateCommand.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
            "--apply",
            "--allow-dirty",
        ])
        do {
            try await secondApply.run()
            XCTFail("Expected the active recovery marker to refuse another apply")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.localizedCaseInsensitiveContains("incomplete"),
                "Expected incomplete-migration refusal, got: \(error)"
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Podfile")), originalPodfile)
        XCTAssertEqual(
            try regularFileContents(beneath: backup.appendingPathComponent("App.xcodeproj")),
            originalProject
        )
    }

    /// This is deliberately a normal no-op when XCTest invokes the whole suite.
    /// Parent cases select it explicitly in a fresh XCTest process and provide the
    /// test-only configuration below. Production code never reads these values.
    func testChildProcessRaisesConfiguredSignal() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let rootPath = environment[Self.helperRootEnvironment],
            let projectPath = environment[Self.helperProjectEnvironment],
            let stageName = environment[Self.helperStageEnvironment],
            let signalText = environment[Self.helperSignalEnvironment],
            let signal = Int32(signalText)
        else {
            return
        }

        do {
            var command = try MigrateCommand.parse([
                "--path", rootPath,
                "--project", projectPath,
                "--apply",
                "--allow-dirty",
            ])
            try await command.run(checkpoint: { stage in
                guard Self.matches(stage, configuredAs: stageName) else { return }
                guard Darwin.raise(signal) == 0 else {
                    Darwin.exit(1)
                }
            })
            Darwin.exit(1)
        } catch let exitCode as ExitCode {
            Darwin.exit(exitCode.rawValue)
        } catch {
            Darwin.exit(1)
        }
    }

    func testIncompleteMarkerIsRefusedBeforeCorruptPlanOrProjectParsingEvenWithAllowDirty() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let stateDirectory = fixture.root.appendingPathComponent(".pkglift", isDirectory: true)
        let marker = stateDirectory.appendingPathComponent("migration-in-progress")
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try Data("not a valid marker".utf8).write(to: marker)
        try Data("not JSON".utf8).write(to: stateDirectory.appendingPathComponent("plan.json"))
        try Data("not an Xcode project".utf8).write(
            to: fixture.project.appendingPathComponent("project.pbxproj")
        )

        var command = try MigrateCommand.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
            "--apply",
            "--allow-dirty",
        ])

        do {
            try await command.run()
            XCTFail("Expected the incomplete migration marker to be refused")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.localizedCaseInsensitiveContains("incomplete"),
                "Expected incomplete-migration refusal, got: \(error)"
            )
        }
    }

    func testDryRunDoesNotCreateRecoveryState() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await writePlan(for: fixture)

        let marker = fixture.root
            .appendingPathComponent(".pkglift", isDirectory: true)
            .appendingPathComponent("migration-in-progress")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))

        var command = try MigrateCommand.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
        ])
        try await command.run()

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    private func assertInterruptedMigrationRollsBack(
        stage: MigrationStage,
        signal: Int32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await writePlan(for: fixture)

        let podfile = fixture.root.appendingPathComponent("Podfile")
        let nestedAuxiliary = fixture.project
            .appendingPathComponent("xcshareddata", isDirectory: true)
            .appendingPathComponent("PkgLiftFixture.xcconfig")
        try FileManager.default.createDirectory(
            at: nestedAuxiliary.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("ORIGINAL_NESTED_AUXILIARY\n".utf8).write(to: nestedAuxiliary)

        let originalPodfile = try Data(contentsOf: podfile)
        let originalProject = try regularFileContents(beneath: fixture.project)

        let terminationStatus = try runChildProcess(
            fixture: fixture,
            stage: stage,
            signal: signal
        )
        XCTAssertEqual(terminationStatus, signal == SIGINT ? 130 : 143, file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: podfile), originalPodfile, file: file, line: line)
        XCTAssertEqual(
            try regularFileContents(beneath: fixture.project),
            originalProject,
            file: file,
            line: line
        )

        let backup = fixture.root
            .appendingPathComponent(".pkglift", isDirectory: true)
            .appendingPathComponent("backup", isDirectory: true)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Podfile")), originalPodfile)
        XCTAssertEqual(
            try regularFileContents(beneath: backup.appendingPathComponent("App.xcodeproj")),
            originalProject
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: backup.deletingLastPathComponent().appendingPathComponent("migration-in-progress").path
            )
        )
    }

    private func runChildProcess(
        fixture: (root: URL, project: URL),
        stage: MigrationStage,
        signal: Int32,
        expectsRegularExit: Bool = true
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = try xctestExecutableURL()
        process.arguments = [
            "-XCTest",
            "PkgLiftCLITests.MigrateInterruptionTests/testChildProcessRaisesConfiguredSignal",
            Bundle(for: MigrateInterruptionTests.self).bundleURL.path,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment[Self.helperRootEnvironment] = fixture.root.path
        environment[Self.helperProjectEnvironment] = fixture.project.path
        environment[Self.helperStageEnvironment] = Self.name(for: stage)
        environment[Self.helperSignalEnvironment] = String(signal)
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + 10) == .success else {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            XCTFail("Interrupted migration child process did not exit within 10 seconds")
            return -1
        }
        XCTAssertEqual(
            process.terminationReason,
            expectsRegularExit ? .exit : .uncaughtSignal
        )
        return process.terminationStatus
    }

    private func xctestExecutableURL() throws -> URL {
        let lookup = Process()
        lookup.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        lookup.arguments = ["--find", "xctest"]
        let output = Pipe()
        lookup.standardOutput = output
        lookup.standardError = FileHandle.nullDevice
        try lookup.run()
        lookup.waitUntilExit()
        guard lookup.terminationStatus == 0 else {
            throw CocoaError(.fileNoSuchFile)
        }
        let path = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }
        return URL(fileURLWithPath: path)
    }

    private static func matches(_ stage: MigrationStage, configuredAs name: String) -> Bool {
        name == Self.name(for: stage)
    }

    private static func name(for stage: MigrationStage) -> String {
        switch stage {
        case .beforeMutation:
            return "beforeMutation"
        case .podfileWritten:
            return "podfileWritten"
        case .packageAdded(let index):
            return "packageAdded:\(index)"
        case .productLinked(let index):
            return "productLinked:\(index)"
        }
    }

    private func writePlan(for fixture: (root: URL, project: URL)) async throws {
        var command = try PlanCommand.parse([
            "--path", fixture.root.path,
            "--project", fixture.project.path,
        ])
        try await command.run()
    }

    private func makeFixture() throws -> (root: URL, project: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftInterruption-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "target 'App' do\n  pod 'Alamofire'\nend\n".write(
            to: root.appendingPathComponent("Podfile"),
            atomically: true,
            encoding: .utf8
        )
        try "PODS:\n  - Alamofire (5.0.0)\nDEPENDENCIES:\n  - Alamofire\n".write(
            to: root.appendingPathComponent("Podfile.lock"),
            atomically: true,
            encoding: .utf8
        )

        let projectURL = root.appendingPathComponent("App.xcodeproj", isDirectory: true)
        let projectConfigurations = XCConfigurationList()
        let targetConfigurations = XCConfigurationList()
        let sourceReference = PBXFileReference(
            sourceTree: .group,
            lastKnownFileType: "sourcecode.swift",
            path: "AppSource.swift"
        )
        let sourceBuildFile = PBXBuildFile(file: sourceReference)
        let sources = PBXSourcesBuildPhase(files: [sourceBuildFile])
        let frameworks = PBXFrameworksBuildPhase(files: [])
        let target = PBXNativeTarget(
            name: "App",
            buildConfigurationList: targetConfigurations,
            buildPhases: [sources, frameworks],
            productName: "App.app",
            productType: .application
        )
        let mainGroup = PBXGroup(children: [sourceReference], sourceTree: .group, name: "Main")
        let rootProject = PBXProject(
            name: "App",
            buildConfigurationList: projectConfigurations,
            compatibilityVersion: "Xcode 15.0",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup,
            targets: [target]
        )
        let project = PBXProj(
            rootObject: rootProject,
            objectVersion: 56,
            archiveVersion: 1,
            classes: [:],
            objects: []
        )
        [
            projectConfigurations,
            targetConfigurations,
            sourceReference,
            sourceBuildFile,
            sources,
            frameworks,
            target,
            mainGroup,
            rootProject,
        ].forEach { project.add(object: $0) }
        try XcodeProj(workspace: XCWorkspace(), pbxproj: project).write(path: Path(projectURL.path))

        return (root, projectURL)
    }

    private func regularFileContents(beneath root: URL) throws -> [String: Data] {
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var contents: [String: Data] = [:]
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
            let relativePath = String(canonicalURL.path.dropFirst(canonicalRoot.path.count + 1))
            contents[relativePath] = try Data(contentsOf: canonicalURL)
        }
        return contents
    }
}
