import Foundation
import PkgLiftCore
import PkgLiftXcode

public enum MigrationEngineError: LocalizedError, Sendable, Equatable {
    case projectContextRequired
    case missingPodDeclarations([String])

    public var errorDescription: String? {
        switch self {
        case .projectContextRequired:
            return "Applying a migration requires a validated Xcode project and target context. Use the full migration execution API."
        case .missingPodDeclarations(let dependencies):
            return "Automatic migration refused because these exact Podfile declarations were not found: \(dependencies.joined(separator: ", ")). No files were changed."
        }
    }
}

/// Executes only operations that have already passed `MigrationPlanPreflight`.
public struct MigrationEngine: Sendable {
    public init() {}

    /// Backward-compatible plan preview. Applying through this legacy overload
    /// is refused because it has no Xcode project/target context.
    public func execute(planURL: URL, podfileURL: URL, isDryRun: Bool = true) throws {
        let plan = try loadPlan(at: planURL)
        if !isDryRun {
            throw MigrationEngineError.projectContextRequired
        }

        let autoEntries = plan.autoEntries
        if autoEntries.isEmpty {
            print("No AUTO migrations planned.")
            return
        }
        print("DRY RUN: The following pods would be migrated after full preflight:")
        for entry in autoEntries {
            print("- \(entry.podName)")
        }
    }

    /// Applies a validated execution contract atomically across the Podfile and
    /// `.xcodeproj` directory. No fallback decisions are made here.
    public func execute(
        prepared: PreparedMigration,
        podfileURL: URL,
        projectPath: String,
        backupDir: URL
    ) throws {
        let podfileEditor = PodfileEditor()
        let podfileContent = try String(contentsOf: podfileURL, encoding: .utf8)
        let podfileEdit = podfileEditor.removeWithResult(
            pods: prepared.podsToRemove,
            from: podfileContent
        )
        let missingPodDeclarations = prepared.podsToRemove.subtracting(podfileEdit.removedPods)
        if !missingPodDeclarations.isEmpty {
            throw MigrationEngineError.missingPodDeclarations(missingPodDeclarations.sorted())
        }

        let projectURL = URL(fileURLWithPath: projectPath)
        let xcodeEditor = XcodeProjectEditor()
        try AtomicMigration().perform(
            files: [podfileURL, projectURL],
            backupDir: backupDir
        ) {
            try podfileEdit.content.write(to: podfileURL, atomically: true, encoding: .utf8)

            for package in prepared.packagesToAdd {
                try xcodeEditor.addSwiftPMPackage(
                    repositoryURL: package.repositoryURL,
                    requirement: package.requirement,
                    to: projectPath
                )
            }

            for link in prepared.productsToLink {
                try xcodeEditor.linkSwiftPMProduct(
                    productName: link.productName,
                    toTarget: link.targetName,
                    repositoryURL: link.repositoryURL,
                    in: projectPath
                )
            }
        }
    }

    private func loadPlan(at url: URL) throws -> MigrationPlan {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MigrationPlan.self, from: data)
    }
}
