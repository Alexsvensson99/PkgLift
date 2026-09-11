import ArgumentParser
import Darwin
import Dispatch
import Foundation
import PathKit
import XCTest
import XcodeProj
import PkgLiftMigration
import PkgLiftSignalTestSupport
@testable import PkgLiftCLI

final class MigrateInterruptionTests: XCTestCase {
    private static let helperRootEnvironment = "PKGLIFT_TEST_INTERRUPT_ROOT"
    private static let helperProjectEnvironment = "PKGLIFT_TEST_INTERRUPT_PROJECT"
    private static let helperStageEnvironment = "PKGLIFT_TEST_INTERRUPT_STAGE"
    private static let helperSignalEnvironment = "PKGLIFT_TEST_INTERRUPT_SIGNAL"
    private static let beforeSignalRestoreStage = "beforeSignalRestore"
    private static let delayedHandlerAfterRestoreStage = "delayedHandlerAfterRestore"
    private static let delayedHandlerWithPriorFailureStage = "delayedHandlerWithPriorFailure"
    private static let reinstallAfterFinishStage = "reinstallAfterFinish"

    func testSIGINTAfterPodfileWriteRollsBackAndPreservesBackup() async throws {
        try await assertInterruptedMigrationRollsBack(stage: .podfileWritten, signal: SIGINT)
    }

    func testSIGINTAfterPackageAddRollsBackAndPreservesBackup() async throws {
        try await assertInterruptedMigrationRollsBack(stage: .packageAdded(0), signal: SIGINT)
    }

    func testSIGINTAfterProductLinkRollsBackAndPreservesBackup() async throws {
        try await assertInterruptedMigrationRollsBack(stage: .productLinked(0), signal: SIGINT)
    }

    func testSIGTERMAfterPodfileWriteRollsBackAndPreservesBackup() async throws {
        try await assertInterruptedMigrationRollsBack(stage: .podfileWritten, signal: SIGTERM)
    }

    func testSIGTERMAfterPackageAddRollsBackAndPreservesBackup() async throws {
        try await assertInterruptedMigrationRollsBack(stage: .packageAdded(0), signal: SIGTERM)
    }

    func testSIGTERMAfterProductLinkRollsBackAndPreservesBackup() async throws {
        try await assertInterruptedMigrationRollsBack(stage: .productLinked(0), signal: SIGTERM)
    }

    func testSIGINTAfterCompletedMigrationBeforeHandlerRestoreExits130WithFullyMigratedFiles() async throws {
        try await assertLateSignalLeavesCompletedMigration(signal: SIGINT)
    }

    func testSIGTERMAfterCompletedMigrationBeforeHandlerRestoreExits143WithFullyMigratedFiles() async throws {
        try await assertLateSignalLeavesCompletedMigration(signal: SIGTERM)
    }

    func testDelayedSIGINTHandlerAfterRestoreExits130WithFullyMigratedFiles() async throws {
        try await assertDelayedHandlerLeavesCompletedMigration(signal: SIGINT)
    }

    func testDelayedSIGTERMHandlerAfterRestoreExits143WithFullyMigratedFiles() async throws {
        try await assertDelayedHandlerLeavesCompletedMigration(signal: SIGTERM)
    }

    func testDelayedSIGTERMAfterEarlierMigrationFailurePreservesOriginalFailureAndRollback() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await writePlan(for: fixture)

        let originalPodfile = try Data(contentsOf: fixture.root.appendingPathComponent("Podfile"))
        let originalProject = try regularFileContents(beneath: fixture.project)
        let result = try runChildProcess(
            fixture: fixture,
            stageName: Self.delayedHandlerWithPriorFailureStage,
            signal: SIGTERM
        )

        XCTAssertEqual(result.terminationStatus, 1)
        XCTAssertTrue(
            result.standardError.contains(ChildInjectedFailure.message),
            "Expected the original failure diagnostic, got: \(result.standardError)"
        )
        XCTAssertEqual(
            try Data(contentsOf: fixture.root.appendingPathComponent("Podfile")),
            originalPodfile
        )
        XCTAssertEqual(try regularFileContents(beneath: fixture.project), originalProject)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.root.appendingPathComponent(".pkglift/migration-in-progress").path
            )
        )
    }

    func testSignalHandlerOwnershipCannotBeReinstalledInSameProcess() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await writePlan(for: fixture)

        let result = try runChildProcess(
            fixture: fixture,
            stageName: Self.reinstallAfterFinishStage,
            signal: SIGINT
        )
        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertTrue(
            result.standardError.contains("reinstall refused with EALREADY"),
            "Expected typed one-shot ownership refusal, got: \(result.standardError)"
        )
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
        XCTAssertEqual(terminationStatus.terminationStatus, SIGKILL)

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
            try await command.run(
                checkpoint: { stage in
                    if stageName == Self.delayedHandlerWithPriorFailureStage,
                       stage == .podfileWritten {
                        throw ChildInjectedFailure()
                    }
                    guard Self.matches(stage, configuredAs: stageName) else { return }
                    // SIGKILL cannot be handled. For handled signals, wait for
                    // capture before the engine advances to its next checkpoint.
                    let delivered = signal == SIGKILL
                        ? Darwin.raise(signal) == 0
                        : Self.raiseSynchronously(signal)
                    guard delivered else {
                        Darwin.exit(1)
                    }
                },
                beforeSignalRestore: { signals in
                    if stageName == Self.beforeSignalRestoreStage {
                        guard Self.raiseSynchronously(signal) else {
                            Darwin.exit(1)
                        }
                        let capturedSignal = signals.capturedInterruption()?.signal ?? 0
                        guard capturedSignal == signal else {
                            Self.writeChildDiagnostic(
                                "handler did not capture signal: expected=\(signal) captured=\(capturedSignal)"
                            )
                            Darwin.exit(1)
                        }
                    } else if Self.isDelayedHandlerStage(stageName) {
                        Self.startDelayedSignal(signal)
                    }
                },
                afterSignalRestore: {
                    if Self.isDelayedHandlerStage(stageName) {
                        Self.releaseDelayedSignalAndWait()
                    }
                    if stageName == Self.reinstallAfterFinishStage {
                        do {
                            _ = try MigrationSignals()
                            Self.writeChildDiagnostic("signal handlers unexpectedly reinstalled")
                            Darwin.exit(1)
                        } catch MigrationSignals.SignalError.installationFailed(let code)
                            where code == EALREADY {
                            Self.writeChildDiagnostic("reinstall refused with EALREADY")
                            Darwin.exit(0)
                        } catch {
                            Self.writeChildDiagnostic(
                                "unexpected reinstallation error: \(String(reflecting: error))"
                            )
                            Darwin.exit(1)
                        }
                    }
                }
            )
            Darwin.exit(1)
        } catch let exitCode as ExitCode {
            Darwin.exit(exitCode.rawValue)
        } catch AtomicMigration.MigrationError.actionFailed(let underlyingError) {
            if let injectedFailure = underlyingError as? ChildInjectedFailure {
                Self.writeChildDiagnostic(
                    "preserved typed failure: \(injectedFailure.localizedDescription)"
                )
            } else {
                Self.writeChildDiagnostic(
                    "unexpected action failure: \(String(reflecting: underlyingError))"
                )
            }
            Darwin.exit(1)
        } catch {
            Self.writeChildDiagnostic(
                "unexpected child error: \(error.localizedDescription) [\(String(reflecting: error))]"
            )
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
        XCTAssertEqual(
            terminationStatus.terminationStatus,
            signal == SIGINT ? 130 : 143,
            file: file,
            line: line
        )
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

    private func assertLateSignalLeavesCompletedMigration(
        signal: Int32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await assertSignalLeavesCompletedMigration(
            signal: signal,
            stageName: Self.beforeSignalRestoreStage,
            expectsSwiftMessage: true,
            file: file,
            line: line
        )
    }

    private func assertDelayedHandlerLeavesCompletedMigration(
        signal: Int32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await assertSignalLeavesCompletedMigration(
            signal: signal,
            stageName: Self.delayedHandlerAfterRestoreStage,
            expectsSwiftMessage: false,
            file: file,
            line: line
        )
    }

    private func assertSignalLeavesCompletedMigration(
        signal: Int32,
        stageName: String,
        expectsSwiftMessage: Bool,
        file: StaticString,
        line: UInt
    ) async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await writePlan(for: fixture)

        let result = try runChildProcess(
            fixture: fixture,
            stageName: stageName,
            signal: signal
        )
        XCTAssertEqual(
            result.terminationStatus,
            signal == SIGINT ? 130 : 143,
            file: file,
            line: line
        )
        if expectsSwiftMessage {
            XCTAssertTrue(
                result.standardError.contains(
                    "Migration completed before the interruption was observed; files are fully migrated."
                ),
                "Expected the terminal fully-migrated message, got: \(result.standardError)",
                file: file,
                line: line
            )
        }

        let podfile = try String(
            contentsOf: fixture.root.appendingPathComponent("Podfile"),
            encoding: .utf8
        )
        XCTAssertFalse(podfile.contains("pod 'Alamofire'"), file: file, line: line)

        let migratedProject = try XcodeProj(pathString: fixture.project.path)
        let rootProject = try XCTUnwrap(try migratedProject.pbxproj.rootProject(), file: file, line: line)
        let target = try XCTUnwrap(
            migratedProject.pbxproj.nativeTargets.first { $0.name == "App" },
            file: file,
            line: line
        )
        let frameworks = try XCTUnwrap(try target.frameworksBuildPhase(), file: file, line: line)
        XCTAssertEqual(rootProject.remotePackages.count, 1, file: file, line: line)
        XCTAssertEqual(target.packageProductDependencies?.count, 1, file: file, line: line)
        XCTAssertEqual(frameworks.files?.count, 1, file: file, line: line)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.root
                    .appendingPathComponent(".pkglift", isDirectory: true)
                    .appendingPathComponent("migration-in-progress")
                    .path
            ),
            file: file,
            line: line
        )
    }

    private struct ChildProcessResult {
        let terminationStatus: Int32
        let standardError: String
    }

    private struct ChildInjectedFailure: LocalizedError {
        static let message = "injected prior migration failure"

        var errorDescription: String? { Self.message }
    }

    private func runChildProcess(
        fixture: (root: URL, project: URL),
        stage: MigrationStage,
        signal: Int32,
        expectsRegularExit: Bool = true
    ) throws -> ChildProcessResult {
        try runChildProcess(
            fixture: fixture,
            stageName: Self.name(for: stage),
            signal: signal,
            expectsRegularExit: expectsRegularExit
        )
    }

    private func runChildProcess(
        fixture: (root: URL, project: URL),
        stageName: String,
        signal: Int32,
        expectsRegularExit: Bool = true
    ) throws -> ChildProcessResult {
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
        environment[Self.helperStageEnvironment] = stageName
        environment[Self.helperSignalEnvironment] = String(signal)
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        let standardError = Pipe()
        process.standardError = standardError
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + 10) == .success else {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            XCTFail("Interrupted migration child process did not exit within 10 seconds")
            return ChildProcessResult(terminationStatus: -1, standardError: "")
        }
        XCTAssertEqual(
            process.terminationReason,
            expectsRegularExit ? .exit : .uncaughtSignal
        )
        let errorText = String(
            data: standardError.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return ChildProcessResult(
            terminationStatus: process.terminationStatus,
            standardError: errorText
        )
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

    private static func isDelayedHandlerStage(_ stageName: String) -> Bool {
        stageName == delayedHandlerAfterRestoreStage ||
            stageName == delayedHandlerWithPriorFailureStage
    }

    private static func startDelayedSignal(_ signal: Int32) {
        let installResult = pkglift_test_delayed_signal_install(signal)
        guard installResult == 0 else {
            writeChildDiagnostic("delayed-handler install failed: \(installResult)")
            Darwin.exit(1)
        }

        let worker = Thread {
            guard sendSignalFromCurrentThread(signal) else {
                Darwin.exit(1)
            }
        }
        worker.start()

        let enteredResult = pkglift_test_delayed_signal_wait_until_entered()
        guard enteredResult == 0 else {
            writeChildDiagnostic("delayed handler did not enter: \(enteredResult)")
            Darwin.exit(1)
        }
    }

    private static func releaseDelayedSignalAndWait() {
        let result = pkglift_test_delayed_signal_release_and_wait()
        guard result == 0 else {
            writeChildDiagnostic("delayed handler did not complete: \(result)")
            Darwin.exit(1)
        }
    }

    private static func raiseSynchronously(_ signal: Int32) -> Bool {
        // Darwin rejects pthread_kill on Swift's executor workers. Use a
        // dedicated thread and rendezvous after delivery, without a timing race.
        let finished = DispatchSemaphore(value: 0)
        let worker = Thread {
            guard sendSignalFromCurrentThread(signal) else {
                Darwin.exit(1)
            }
            finished.signal()
        }
        worker.start()
        guard finished.wait(timeout: .now() + 5) == .success else {
            writeChildDiagnostic("dedicated signal thread did not finish")
            return false
        }
        return true
    }

    private static func sendSignalFromCurrentThread(_ signal: Int32) -> Bool {
        var signalSet = sigset_t()
        let emptyResult = sigemptyset(&signalSet)
        let addResult = sigaddset(&signalSet, signal)
        guard emptyResult == 0, addResult == 0 else {
            writeChildDiagnostic("signal-set setup failed: empty=\(emptyResult) add=\(addResult)")
            return false
        }

        var previousMask = sigset_t()
        let unblockResult = pthread_sigmask(SIG_UNBLOCK, &signalSet, &previousMask)
        guard unblockResult == 0 else {
            writeChildDiagnostic("signal unblock failed: \(unblockResult)")
            return false
        }
        let raiseResult = pthread_kill(pthread_self(), signal)
        let restoreResult = pthread_sigmask(SIG_SETMASK, &previousMask, nil)
        guard raiseResult == 0, restoreResult == 0 else {
            writeChildDiagnostic("signal delivery failed: kill=\(raiseResult) restore=\(restoreResult)")
            return false
        }
        return true
    }

    private static func writeChildDiagnostic(_ message: String) {
        FileHandle.standardError.write(Data("PKGLIFT signal-test diagnostic: \(message)\n".utf8))
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
