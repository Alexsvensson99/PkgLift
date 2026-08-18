import Foundation
import XCTest
import PkgLiftCore
@testable import PkgLiftCLI

final class MixedLanguagePilotFixtureTests: XCTestCase {
    func testPinnedPilotWriteRootGuardRejectsPreexistingStatePaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftPilotRoot-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftPilotOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let statePath = root.appendingPathComponent(".pkglift")
        try FileManager.default.createSymbolicLink(
            at: statePath,
            withDestinationURL: outside
        )

        XCTAssertEqual(try pilotWriteRootGuardStatus(for: root), 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: outside.appendingPathComponent("plan.json").path
            )
        )

        try FileManager.default.removeItem(at: statePath)
        XCTAssertEqual(try pilotWriteRootGuardStatus(for: root), 0)

        try FileManager.default.createDirectory(at: statePath, withIntermediateDirectories: false)
        XCTAssertEqual(try pilotWriteRootGuardStatus(for: root), 1)
    }

    func testUnsupportedRubyLexicalVariantsNeverProduceAuto() async throws {
        let podfiles = [
            """
            target('PkgLiftMixedFixture') do
            =begin documentation
              pod('SDWebImage', '5.18.1', modular_headers: true)
            =end
            end
            """,
            """
            target('PkgLiftMixedFixture') do
              puts <<~'1'
                pod('SDWebImage', '5.18.1', modular_headers: true)
              1
            end
            """,
            """
            target('PkgLiftMixedFixture') do
              [].each {
                pod('SDWebImage', '5.18.1', modular_headers: true)
              }
            end
            """,
            """
            puts "
            target('PkgLiftMixedFixture') do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            "
            """,
            """
            target('PkgLiftMixedFixture') do
              false &&
                pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            puts %q(
            target('PkgLiftMixedFixture') do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            )
            """,
            """
            defined?(
              pod('SDWebImage', '5.18.1', modular_headers: true)
            )
            """,
            """
            target('PkgLiftMixedFixture') do
              next
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            target('PkgLiftMixedFixture') do
              pod('GuardPod'); next
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            def pod
            end

            target('PkgLiftMixedFixture') do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            def target
            end

            target('PkgLiftMixedFixture') do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            target('PkgLiftMixedFixture') do
              pod('GuardPod', false ? nil:abort)
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            target('PkgLiftMixedFixture') do
              pod('GuardPod', Kernel::abort)
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            target('PkgLiftMixedFixture') do
              pod('GuardPod', 08)
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            target('PkgLiftMixedFixture') do
              pod('GuardPod', foo: true)
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            source 'https://private.example.invalid/specs'
            target('PkgLiftMixedFixture') do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            workspace 'OtherWorkspace'
            target('PkgLiftMixedFixture') do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            project 'Other.xcodeproj'
            target('PkgLiftMixedFixture') do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            target('PkgLiftMixedFixture') do
              pod('Guard\u{0}Pod')
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            source 'https://example.invalid/specs\u{0}'
            target('PkgLiftMixedFixture') do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            target('PkgLiftMixedFixture')\u{00A0}do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            target('PkgLiftMixedFixture') do
              =begin documentation
              ignored
              =end
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
        ]

        for podfile in podfiles {
            let root = try copyFixture()
            defer { try? FileManager.default.removeItem(at: root) }
            try podfile.write(
                to: root.appendingPathComponent("Podfile"),
                atomically: true,
                encoding: .utf8
            )

            let options = try CommonOptions.parse([
                "--path", root.path,
                "--project", "PkgLiftMixedFixture.xcodeproj",
            ])
            let context = try await CommandContext.load(from: options)
            let analysis = context.buildProjectAnalysis()
            let plan = context.buildMigrationPlan()

            XCTAssertFalse(analysis.candidates.contains {
                $0.pod.name == "SDWebImage" && $0.classification == .auto
            })
            XCTAssertFalse(plan.autoEntries.contains { $0.podName == "SDWebImage" })
        }
    }

    func testTrackedMixedLanguageFixtureProducesOneReviewedAutoAndDryRunIsMutationFree() async throws {
        let root = try copyFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("PkgLiftMixedFixture.xcodeproj")
        let arguments = ["--path", root.path, "--project", project.path]
        let options = try CommonOptions.parse(arguments)
        let context = try await CommandContext.load(from: options)
        let analysis = context.buildProjectAnalysis()
        let directCandidates = analysis.candidates.filter(\.pod.isDirect)
        let candidate = try XCTUnwrap(
            directCandidates.first { $0.pod.name == "SDWebImage" }
        )
        let plan = context.buildMigrationPlan()
        let entry = try XCTUnwrap(plan.entries.first)

        XCTAssertEqual(directCandidates.count, 1)
        XCTAssertEqual(candidate.classification, .auto)
        XCTAssertEqual(candidate.packageCandidate?.supportedConsumerLanguages, [.swift, .objectiveC])
        XCTAssertEqual(plan.autoEntries.map(\.podName), ["SDWebImage"])
        XCTAssertEqual(entry.targetName, "PkgLiftMixedFixture")
        XCTAssertEqual(
            entry.targetSourceProfile,
            TargetSourceProfile(
                languages: [.swift, .objectiveC],
                completeness: .complete
            )
        )

        let swiftSource = try String(
            contentsOf: root.appendingPathComponent("App/AppDelegate.swift"),
            encoding: .utf8
        )
        let objectiveCSource = try String(
            contentsOf: root.appendingPathComponent("App/LegacyImageLoader.m"),
            encoding: .utf8
        )
        XCTAssertTrue(swiftSource.contains("import SDWebImage"))
        XCTAssertTrue(objectiveCSource.contains("#import <SDWebImage/SDWebImage.h>"))

        let protectedPaths = [
            "App/AppDelegate.swift",
            "App/LegacyImageLoader.m",
            "App/Fixture.txt",
        ]
        let protectedBefore = try contents(of: protectedPaths, beneath: root)

        var planCommand = try PlanCommand.parse(arguments)
        try await planCommand.run()
        let beforeDryRun = try treeContents(beneath: root)

        var dryRun = try MigrateCommand.parse(arguments)
        try await dryRun.run()

        XCTAssertEqual(try treeContents(beneath: root), beforeDryRun)
        XCTAssertEqual(try contents(of: protectedPaths, beneath: root), protectedBefore)
    }

    private func copyFixture() throws -> URL {
        let source = packageRoot
            .appendingPathComponent("Fixtures/MixedLanguageSDWebImage", isDirectory: true)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftMixedPilot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: source, to: root)
        return root
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func pilotWriteRootGuardStatus(for root: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            packageRoot
                .appendingPathComponent("Scripts/validate-pinned-pilot-write-root.sh")
                .path,
            root.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func contents(of paths: [String], beneath root: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: paths.map { path in
            (path, try Data(contentsOf: root.appendingPathComponent(path)))
        })
    }

    private func treeContents(beneath root: URL) throws -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var result: [String: Data] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true || values.isSymbolicLink == true else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            if values.isSymbolicLink == true {
                result[relative] = Data(try FileManager.default.destinationOfSymbolicLink(atPath: url.path).utf8)
            } else {
                result[relative] = try Data(contentsOf: url)
            }
        }
        return result
    }
}
