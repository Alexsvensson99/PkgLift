//
//  VerifyCommand.swift
//  PkgLiftCLI
//

import ArgumentParser
import Foundation
import PkgLiftCore
import PkgLiftVerification

struct VerifyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "verify", abstract: "Verify the project structure and build.")

    @OptionGroup var common: CommonOptions

    @Flag(name: .long, help: "Run a build verification.")
    var build: Bool = false

    @Option(name: .long, help: "Explicit scheme to build.")
    var scheme: String?

    mutating func run() async throws {
        let context = try await CommandContext.load(from: common)

        guard let projectPath = context.resolvedProjectPath else {
            throw VerifyError.noProject
        }

        let projectToVerify = context.isWorkspaceSelected
            ? (context.resolvedWorkspacePath ?? projectPath)
            : projectPath

        let verifier = StructuralVerifier()

        var checks: [VerificationCheck] = []
        var issues: [MigrationIssue] = []

        let planExists = FileManager.default.fileExists(atPath: context.planURL.path)
        var planEntries: [PkgLiftCore.MigrationPlanEntry] = []

        if planExists {
            do {
                planEntries = try loadPlan(from: context.planURL).entries
            } catch {
                checks.append(VerificationCheck(
                    name: "plan_load",
                    description: "Load migration plan",
                    passed: false,
                    detail: error.localizedDescription
                ))
                issues.append(MigrationIssue(
                    severity: .error,
                    message: "Unable to read migration plan",
                    detail: error.localizedDescription
                ))
            }
        }

        let migratedPods = planEntries
            .filter { $0.classification == .auto }
            .map(\.podName)
        let expectedPackages = planEntries
            .filter { $0.classification == .auto }
            .compactMap { $0.packageCandidate?.repositoryURL }
            .reduce(into: Set<String>()) { $0.insert($1) }
            .sorted()
        let expectedProducts: [ExpectedPackageProduct] = planEntries
            .filter { $0.classification == .auto }
            .flatMap { entry -> [ExpectedPackageProduct] in
                guard let package = entry.packageCandidate,
                      let targetName = entry.targetName else { return [] }
                return package.products.map {
                    ExpectedPackageProduct(
                        repositoryURL: package.repositoryURL,
                        productName: $0,
                        targetName: targetName
                    )
                }
            }

        let structural = verifier.verify(
            projectPath: projectPath,
            migratedPods: migratedPods,
            expectedPackages: expectedPackages,
            expectedProducts: expectedProducts,
            podfilePath: context.discovery.podfilePath
        )

        checks.append(contentsOf: structural.checks)
        issues.append(contentsOf: structural.issues)

        if build {
            let buildVerifier = BuildVerifier()
            let packageVerification = buildVerifier.resolvePackageDependencies(
                projectPath: projectToVerify,
                isWorkspace: context.isWorkspaceSelected
            )
            checks.append(contentsOf: packageVerification.checks)
            issues.append(contentsOf: packageVerification.issues)

            let buildResult = buildVerifier.buildVerify(
                projectPath: projectToVerify,
                scheme: scheme,
                isWorkspace: context.isWorkspaceSelected
            )
            checks.append(contentsOf: buildResult.checks)
            issues.append(contentsOf: buildResult.issues)
        }

        let final = VerificationResult(
            passed: checks.allSatisfy(\.passed),
            checks: checks,
            issues: issues
        )

        if common.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(final)
            guard let json = String(data: data, encoding: .utf8) else {
                throw VerifyError.encodingFailed
            }
            print(json)
            if !final.passed {
                throw VerifyError.verificationFailed
            }
            return
        }

        print("Verification \(final.passed ? "passed" : "failed")")
        for check in checks {
            let status = check.passed ? "✓" : "✕"
            print("\(status) \(check.name): \(check.description)")
        }

        if !final.issues.isEmpty {
            print("\nIssues:")
            for issue in final.issues {
                print("- \(issue.severity.rawValue): \(issue.message)")
            }
        }

        if !final.passed {
            throw VerifyError.verificationFailed
        }
    }

    private func loadPlan(from url: URL) throws -> PkgLiftCore.MigrationPlan {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PkgLiftCore.MigrationPlan.self, from: data)
    }
}

private enum VerifyError: LocalizedError {
    case noProject
    case encodingFailed
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .noProject:
            return "No analyzable Xcode project found."
        case .encodingFailed:
            return "Unable to encode verify output as JSON."
        case .verificationFailed:
            return "Verification checks failed."
        }
    }
}
