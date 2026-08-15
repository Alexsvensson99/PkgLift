// PkgLiftVerification/StructuralVerifier.swift
// Verifies the structural integrity of a project after migration.

import Foundation
import PkgLiftCore
import PkgLiftXcode
import XcodeProj

public struct ExpectedPackageProduct: Sendable, Equatable {
    public let repositoryURL: String
    public let productName: String
    public let targetName: String

    public init(repositoryURL: String, productName: String, targetName: String) {
        self.repositoryURL = repositoryURL
        self.productName = productName
        self.targetName = targetName
    }
}

/// Verifies the structural integrity of a project after migration.
///
/// Checks that:
/// - The project file parses correctly
/// - SwiftPM package references exist and have valid URLs
/// - Expected products are linked to expected targets
/// - Migrated CocoaPods entries are no longer active
public struct StructuralVerifier: Sendable {
    public init() {}

    /// Verifies the project structure after migration.
    ///
    /// - Parameters:
    ///   - projectPath: The path to the `.xcodeproj` file.
    ///   - migratedPods: Names of pods that were migrated.
    ///   - expectedPackages: Repository URLs of expected SwiftPM packages.
    ///   - podfilePath: Path to the Podfile, if available.
    /// - Returns: A `VerificationResult` indicating success or failure.
    public func verify(
        projectPath: String,
        migratedPods: [String] = [],
        expectedPackages: [String] = [],
        expectedProducts: [ExpectedPackageProduct] = [],
        podfilePath: String? = nil
    ) -> VerificationResult {
        var checks: [VerificationCheck] = []
        var issues: [MigrationIssue] = []

        // Check 1: Project file parses correctly
        let analyzer = XcodeProjectAnalyzer()
        do {
            let result = try analyzer.analyzeProject(at: projectPath)

            checks.append(VerificationCheck(
                name: "project_parses",
                description: "Xcode project file parses correctly",
                passed: true
            ))

            // Check 2: Expected SwiftPM packages are present
            let existingURLs = Set(result.swiftPMState.packages.map { RepositoryIdentity.normalized($0.repositoryURL) })
            for expectedURL in expectedPackages {
                let found = existingURLs.contains(RepositoryIdentity.normalized(expectedURL))
                checks.append(VerificationCheck(
                    name: "package_\(expectedURL)",
                    description: "SwiftPM package reference exists for \(expectedURL)",
                    passed: found,
                    detail: found ? nil : "Package reference not found in project"
                ))
                if !found {
                    issues.append(MigrationIssue(
                        severity: .error,
                        message: "Expected SwiftPM package not found: \(expectedURL)"
                    ))
                }
            }

            for expected in expectedProducts {
                let package = result.swiftPMState.packages.first {
                    RepositoryIdentity.matches($0.repositoryURL, expected.repositoryURL)
                }
                let found = package?.linkedProducts.contains {
                    $0.productName == expected.productName && $0.targetName == expected.targetName
                } == true
                checks.append(VerificationCheck(
                    name: "product_\(expected.productName)_\(expected.targetName)",
                    description: "SwiftPM product '\(expected.productName)' is linked to target '\(expected.targetName)'",
                    passed: found,
                    detail: found ? nil : "Expected package product linkage was not found"
                ))
                if !found {
                    issues.append(MigrationIssue(
                        severity: .error,
                        message: "Expected SwiftPM product link not found",
                        detail: "\(expected.productName) from \(expected.repositoryURL) should be linked to \(expected.targetName)"
                    ))
                }
            }

            // Check 3: No CocoaPods integration remains for migrated pods
            if migratedPods.isEmpty == false && !result.hasCocoaPodsIntegration {
                checks.append(VerificationCheck(
                    name: "cocoapods_removed",
                    description: "CocoaPods integration removed from project",
                    passed: true
                ))
            }

        } catch {
            checks.append(VerificationCheck(
                name: "project_parses",
                description: "Xcode project file parses correctly",
                passed: false,
                detail: error.localizedDescription
            ))
            issues.append(MigrationIssue(
                severity: .error,
                message: "Project file failed to parse",
                detail: error.localizedDescription
            ))
        }

        // Check 4: Podfile no longer contains migrated pods
        if let podfilePath, !migratedPods.isEmpty {
            guard let podfileContent = try? String(contentsOfFile: podfilePath, encoding: .utf8) else {
                checks.append(VerificationCheck(
                    name: "podfile_readable",
                    description: "Podfile can be read for post-migration verification",
                    passed: false,
                    detail: "Unable to read Podfile at \(podfilePath)"
                ))
                issues.append(MigrationIssue(
                    severity: .error,
                    message: "Unable to verify migrated Podfile declarations"
                ))
                return VerificationResult(passed: false, checks: checks, issues: issues)
            }
            for podName in migratedPods {
                let stillPresent = containsPodDeclaration(named: podName, in: podfileContent)
                checks.append(VerificationCheck(
                    name: "pod_removed_\(podName)",
                    description: "Pod '\(podName)' removed from Podfile",
                    passed: !stillPresent,
                    detail: stillPresent ? "Pod declaration still found in Podfile" : nil
                ))
                if stillPresent {
                    issues.append(MigrationIssue(
                        severity: .warning,
                        message: "Pod '\(podName)' still declared in Podfile",
                        dependency: podName
                    ))
                }
            }
        }

        let allPassed = checks.allSatisfy { $0.passed }

        return VerificationResult(
            passed: allPassed,
            checks: checks,
            issues: issues
        )
    }

    private func containsPodDeclaration(named podName: String, in content: String) -> Bool {
        content.components(separatedBy: .newlines).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasPrefix("#"), trimmed.hasPrefix("pod ") else { return false }
            let escaped = NSRegularExpression.escapedPattern(for: podName)
            return trimmed.range(
                of: "^pod\\s+(['\"])\(escaped)\\1(?:\\s*,|\\s*$)",
                options: .regularExpression
            ) != nil
        }
    }
}
