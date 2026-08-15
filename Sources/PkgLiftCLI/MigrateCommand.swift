//
//  MigrateCommand.swift
//  PkgLiftCLI
//

import ArgumentParser
import Foundation
import PkgLiftCore
import PkgLiftCocoaPods
import PkgLiftMigration
import PkgLiftXcode

struct MigrateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "migrate", abstract: "Execute the migration plan.")

    @OptionGroup var common: CommonOptions

    @Flag(name: .long, help: "Apply the migration.")
    var apply: Bool = false

    @Flag(name: .long, help: "Allow running on a dirty git working tree.")
    var allowDirty: Bool = false

    mutating func run() async throws {
        let context = try await CommandContext.load(from: common)
        let plan = try loadPlan(at: context.planURL)

        let autoEntries = plan.entries.filter { $0.classification == .auto && !$0.podName.isEmpty }

        guard !autoEntries.isEmpty else {
            print("No AUTO entries in plan. Nothing to migrate.")
            return
        }

        let availableTargets = context.xcodeAnalysis?.projectInfo.targets.map(\.name) ?? []
        let prepared = try MigrationPlanPreflight().prepare(
            plan: plan,
            availableTargets: availableTargets
        )

        if !apply {
            print("Dry run mode. Add --apply to execute the migration plan.")
            print("\(autoEntries.count) AUTO migration(s):")
            for entry in autoEntries {
                if let package = entry.packageCandidate {
                    print("- \(entry.podName) -> \(package.repositoryURL)")
                } else {
                    print("- \(entry.podName)")
                }
            }
            return
        }

        if !allowDirty {
            let safetyChecker = GitSafetyChecker()
            let safety = try safetyChecker.check(directory: URL(fileURLWithPath: context.discovery.rootPath))

            if !safety.isClean {
                print("Refusing to run migration on a dirty working tree.")
                for file in safety.changedFiles.prefix(20) {
                    print("- \(file)")
                }
                print("Use --allow-dirty if you want to proceed anyway.")
                throw MigrateError.unsafeWorkingTree
            }
        }

        let podfileURL = context.discovery.podfilePath.map { URL(fileURLWithPath: $0) }
        let projectPath = context.resolvedProjectPath

        guard let podfileURL, let projectPath else {
            throw MigrateError.noProject
        }

        guard URL(fileURLWithPath: plan.projectPath).standardized.path == URL(fileURLWithPath: projectPath).standardized.path else {
            throw MigrateError.planProjectMismatch(planned: plan.projectPath, current: projectPath)
        }

        let backupDir = context.planURL.deletingLastPathComponent().appendingPathComponent("backup")
        try MigrationEngine().execute(
            prepared: prepared,
            podfileURL: podfileURL,
            projectPath: projectPath,
            backupDir: backupDir
        )

        print("Applied \(autoEntries.count) validated AUTO migration(s).")
        print("Run `pod install` to update the remaining CocoaPods integration, then run `pkglift verify`.")
    }

    private func loadPlan(at url: URL) throws -> PkgLiftCore.MigrationPlan {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PkgLiftCore.MigrationPlan.self, from: data)
    }
}

private enum MigrateError: LocalizedError {
    case noProject
    case unsafeWorkingTree
    case planProjectMismatch(planned: String, current: String)

    var errorDescription: String? {
        switch self {
        case .noProject:
            return "Automatic migration requires both a Podfile and a concrete Xcode project."
        case .unsafeWorkingTree:
            return "Working tree has uncommitted changes."
        case .planProjectMismatch(let planned, let current):
            return "Plan targets '\(planned)', but the current Xcode project is '\(current)'. Regenerate the plan for this project."
        }
    }
}
