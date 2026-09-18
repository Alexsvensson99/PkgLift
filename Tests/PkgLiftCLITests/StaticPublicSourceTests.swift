import Foundation
import XCTest
import PkgLiftCore
import PkgLiftMigration
@testable import PkgLiftCLI

final class StaticPublicSourceTests: XCTestCase {
    private let officialSource = "https://github.com/CocoaPods/Specs.git"

    func testExplicitPublicSourceProducesBoundPlanAndInertDryRun() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let arguments = arguments(for: root)
        let context = try await CommandContext.load(from: CommonOptions.parse(arguments))
        let plan = context.buildMigrationPlan()
        let entry = try XCTUnwrap(plan.autoEntries.first)
        XCTAssertEqual(plan.autoEntries.map(\.podName), ["SDWebImage"])
        XCTAssertEqual(entry.registrySourceProvenance?.status, .matchedExplicitPublic)
        XCTAssertEqual(entry.registrySourceProvenance?.declarations.count, 1)
        XCTAssertEqual(entry.registrySourceProvenance?.lockfile?.repositories, [.cocoaPodsSpecsGit])
        let decoded = try JSONDecoder().decode(MigrationPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded.entries.first?.registrySourceProvenance, entry.registrySourceProvenance)

        var command = try PlanCommand.parse(arguments)
        try await command.run()
        let before = try snapshot(root)
        var dryRun = try MigrateCommand.parse(arguments)
        try await dryRun.run()
        XCTAssertEqual(try snapshot(root), before)
    }

    func testMissingOrDifferentLockOriginCannotAuthorizeAuto() async throws {
        for repository in [nil, "trunk", "https://private.example.invalid/specs"] as [String?] {
            let root = try makeFixture(repository: repository)
            defer { try? FileManager.default.removeItem(at: root) }
            let context = try await CommandContext.load(from: CommonOptions.parse(arguments(for: root)))
            XCTAssertTrue(context.buildMigrationPlan().autoEntries.isEmpty)
            let candidate = try XCTUnwrap(context.buildProjectAnalysis().candidates.first {
                $0.pod.name == "SDWebImage" && $0.pod.isDirect
            })
            XCTAssertEqual(candidate.classification, .review)
            XCTAssertNotNil(candidate.pod.registrySourceProvenance)
        }
    }

    func testChangedLockOriginRefusesSavedPlanBeforeAnyWrite() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let arguments = arguments(for: root)
        var command = try PlanCommand.parse(arguments)
        try await command.run()
        let lock = root.appendingPathComponent("Podfile.lock")
        let content = try String(contentsOf: lock, encoding: .utf8)
        try content.replacingOccurrences(of: officialSource, with: "https://private.example.invalid/specs")
            .write(to: lock, atomically: true, encoding: .utf8)
        let before = try snapshot(root)
        var apply = try MigrateCommand.parse(arguments + ["--apply"])
        do {
            try await apply.run()
            XCTFail("Changed registry origin must invalidate the saved AUTO plan")
        } catch {
            XCTAssertEqual(error as? MigrationPlanPreflightError,
                           .staleRegistrySourceProvenance(dependency: "SDWebImage"))
            XCTAssertEqual(try snapshot(root), before)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".pkglift/backup").path))
    }

    private func arguments(for root: URL) -> [String] {
        ["--path", root.path, "--project", "PkgLiftMixedFixture.xcodeproj"]
    }

    private func makeFixture(repository: String? = "https://github.com/CocoaPods/Specs.git") throws -> URL {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftPublicSource-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: package.appendingPathComponent("Fixtures/MixedLanguageSDWebImage"), to: root)
        let podfile = """
        source '\(officialSource)'
        platform:ios,'15.0'
        target 'PkgLiftMixedFixture' do
          pod 'SDWebImage', '5.18.1'
        end

        """
        try podfile.write(to: root.appendingPathComponent("Podfile"), atomically: true, encoding: .utf8)
        var lock = """
        PODS:
          - SDWebImage (5.18.1):
            - SDWebImage/Core (= 5.18.1)
          - SDWebImage/Core (5.18.1)
        DEPENDENCIES:
          - SDWebImage (= 5.18.1)

        """
        if let repository {
            lock += "SPEC REPOS:\n  \(repository):\n    - SDWebImage\n"
        }
        try lock.write(to: root.appendingPathComponent("Podfile.lock"), atomically: true, encoding: .utf8)
        return root
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: []
        ))
        var result: [String: Data] = [:]
        for case let file as URL in enumerator {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(file.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: file)
            }
        }
        return result
    }
}
