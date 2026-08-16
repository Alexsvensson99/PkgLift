import Foundation
import XCTest
import PkgLiftCore
@testable import PkgLiftCLI

final class MixedLanguagePilotFixtureTests: XCTestCase {
    func testTrackedMixedLanguageFixtureProducesOneReviewedAutoAndDryRunIsMutationFree() async throws {
        let source = packageRoot
            .appendingPathComponent("Fixtures/MixedLanguageSDWebImage", isDirectory: true)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftMixedPilot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: source, to: root)
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

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
