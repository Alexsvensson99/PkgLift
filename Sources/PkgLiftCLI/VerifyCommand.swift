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

    @Option(name: .long, help: "Explicit Xcode build configuration, such as Debug or Release.")
    var configuration: String?

    @Option(name: .long, help: "Explicit xcodebuild destination string.")
    var destination: String?

    @Option(name: .long, help: "Explicit SDK passed to xcodebuild, such as iphonesimulator.")
    var sdk: String?

    @Option(name: .long, help: "Derived-data directory. Relative paths are resolved beneath --path.")
    var derivedDataPath: String?

    mutating func run() async throws {
        let buildOptions = try normalizedBuildOptions()
        if !build && (scheme != nil || !buildOptions.isEmpty) {
            throw VerifyError.buildOptionsRequireBuild
        }

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
            guard let scheme else {
                checks.append(VerificationCheck(
                    name: "scheme_specified",
                    description: "Build scheme is specified",
                    passed: false,
                    detail: "No scheme specified. Use --scheme to select a build scheme."
                ))
                issues.append(MigrationIssue(
                    severity: .error,
                    message: "Build verification requires an explicit --scheme",
                    detail: "PkgLift does not guess which scheme to build."
                ))
                try finish(checks: checks, issues: issues)
                return
            }

            let validatedScheme: String
            do {
                validatedScheme = try BuildVerifier.validatedScheme(scheme)
                _ = try BuildVerifier.buildArguments(
                    projectPath: projectToVerify,
                    scheme: validatedScheme,
                    isWorkspace: context.isWorkspaceSelected,
                    options: buildOptions
                )
                _ = try BuildVerifier.resolvePackageArguments(
                    projectPath: projectToVerify,
                    scheme: validatedScheme,
                    isWorkspace: context.isWorkspaceSelected,
                    options: buildOptions
                )
            } catch {
                checks.append(VerificationCheck(
                    name: "build_options_valid",
                    description: "Build verification options are valid",
                    passed: false,
                    detail: error.localizedDescription
                ))
                issues.append(MigrationIssue(
                    severity: .error,
                    message: "Invalid build verification options",
                    detail: error.localizedDescription
                ))
                try finish(checks: checks, issues: issues)
                return
            }

            checks.append(VerificationCheck(
                name: "build_settings",
                description: "Effective build verification settings were recorded",
                passed: true,
                detail: "scheme=<provided>, \(buildOptions.redactedSummary)"
            ))

            let buildVerifier = BuildVerifier()
            let packageVerification = buildVerifier.resolvePackageDependencies(
                projectPath: projectToVerify,
                scheme: validatedScheme,
                isWorkspace: context.isWorkspaceSelected,
                options: buildOptions
            )
            checks.append(contentsOf: packageVerification.checks)
            issues.append(contentsOf: packageVerification.issues)

            let buildResult = buildVerifier.buildVerify(
                projectPath: projectToVerify,
                scheme: validatedScheme,
                isWorkspace: context.isWorkspaceSelected,
                options: buildOptions
            )
            checks.append(contentsOf: buildResult.checks)
            issues.append(contentsOf: buildResult.issues)
        }

        try finish(checks: checks, issues: issues)
    }

    static func resolveDerivedDataPath(_ value: String?, rootPath: String) -> String? {
        guard let value else { return nil }

        if (value as NSString).isAbsolutePath {
            return URL(fileURLWithPath: value, isDirectory: true)
                .standardizedFileURL
                .path
        }

        return URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
            .appendingPathComponent(value, isDirectory: true)
            .standardizedFileURL
            .path
    }

    private func normalizedBuildOptions() throws -> BuildVerificationOptions {
        let rawOptions = try BuildVerificationOptions(
            configuration: configuration,
            destination: destination,
            sdk: sdk,
            derivedDataPath: derivedDataPath
        ).validated()

        return BuildVerificationOptions(
            configuration: rawOptions.configuration,
            destination: rawOptions.destination,
            sdk: rawOptions.sdk,
            derivedDataPath: Self.resolveDerivedDataPath(
                rawOptions.derivedDataPath,
                rootPath: common.path
            )
        )
    }

    @discardableResult
    private func finish(
        checks: [VerificationCheck],
        issues: [MigrationIssue]
    ) throws -> VerificationResult {
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
            return final
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
        return final
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
    case buildOptionsRequireBuild
    case encodingFailed
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .noProject:
            return "No analyzable Xcode project found."
        case .buildOptionsRequireBuild:
            return "--scheme, --configuration, --destination, --sdk, and --derived-data-path require --build."
        case .encodingFailed:
            return "Unable to encode verify output as JSON."
        case .verificationFailed:
            return "Verification checks failed."
        }
    }
}
