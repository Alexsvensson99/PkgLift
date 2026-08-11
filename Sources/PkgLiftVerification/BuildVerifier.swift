// PkgLiftVerification/BuildVerifier.swift
// Optional build verification using xcodebuild.

import Foundation
import PkgLiftCore

/// Verifies a project builds correctly after migration.
///
/// Uses `xcodebuild` for:
/// - Package dependency resolution
/// - Optional full build verification
///
/// When multiple schemes exist and none is specified,
/// reports ambiguity rather than guessing.
public struct BuildVerifier: Sendable {
    private let processRunner: ProcessRunner

    public init(processRunner: ProcessRunner = ProcessRunner()) {
        self.processRunner = processRunner
    }

    /// Resolves SwiftPM package dependencies.
    ///
    /// - Parameters:
    ///   - projectPath: Path to `.xcodeproj` or `.xcworkspace`.
    ///   - isWorkspace: Whether the path is a workspace.
    /// - Returns: A `VerificationResult`.
    public func resolvePackageDependencies(
        projectPath: String,
        isWorkspace: Bool = false
    ) -> VerificationResult {
        var checks: [VerificationCheck] = []
        var issues: [MigrationIssue] = []

        guard let xcodebuild = processRunner.findExecutable("xcodebuild") else {
            checks.append(VerificationCheck(
                name: "xcodebuild_available",
                description: "xcodebuild is available",
                passed: false,
                detail: "xcodebuild not found in PATH. Install Xcode Command Line Tools."
            ))
            return VerificationResult(passed: false, checks: checks, issues: issues)
        }

        var arguments = ["-resolvePackageDependencies"]
        if isWorkspace {
            arguments += ["-workspace", projectPath]
        } else {
            arguments += ["-project", projectPath]
        }

        do {
            let result = try processRunner.run(
                executable: xcodebuild,
                arguments: arguments
            )

            let passed = result.succeeded
            checks.append(VerificationCheck(
                name: "resolve_dependencies",
                description: "SwiftPM package dependencies resolve successfully",
                passed: passed,
                detail: passed ? nil : result.stderr
            ))

            if !passed {
                issues.append(MigrationIssue(
                    severity: .error,
                    message: "Package dependency resolution failed",
                    detail: result.stderr
                ))
            }
        } catch {
            checks.append(VerificationCheck(
                name: "resolve_dependencies",
                description: "SwiftPM package dependencies resolve successfully",
                passed: false,
                detail: error.localizedDescription
            ))
            issues.append(MigrationIssue(
                severity: .error,
                message: "Failed to run xcodebuild",
                detail: error.localizedDescription
            ))
        }

        let allPassed = checks.allSatisfy { $0.passed }
        return VerificationResult(passed: allPassed, checks: checks, issues: issues)
    }

    /// Runs a full build verification.
    ///
    /// - Parameters:
    ///   - projectPath: Path to `.xcodeproj` or `.xcworkspace`.
    ///   - scheme: The scheme to build. Required when multiple schemes exist.
    ///   - isWorkspace: Whether the path is a workspace.
    /// - Returns: A `VerificationResult`.
    public func buildVerify(
        projectPath: String,
        scheme: String?,
        isWorkspace: Bool = false
    ) -> VerificationResult {
        var checks: [VerificationCheck] = []
        var issues: [MigrationIssue] = []

        guard let xcodebuild = processRunner.findExecutable("xcodebuild") else {
            checks.append(VerificationCheck(
                name: "xcodebuild_available",
                description: "xcodebuild is available",
                passed: false,
                detail: "xcodebuild not found in PATH"
            ))
            return VerificationResult(passed: false, checks: checks, issues: issues)
        }

        guard let scheme = scheme else {
            checks.append(VerificationCheck(
                name: "scheme_specified",
                description: "Build scheme is specified",
                passed: false,
                detail: "No scheme specified. Use --scheme to select a build scheme."
            ))
            issues.append(MigrationIssue(
                severity: .error,
                message: "Build verification requires an explicit --scheme when multiple schemes may exist",
                detail: "PkgLift does not guess which scheme to build."
            ))
            return VerificationResult(passed: false, checks: checks, issues: issues)
        }

        var arguments = ["build", "-scheme", scheme]
        if isWorkspace {
            arguments += ["-workspace", projectPath]
        } else {
            arguments += ["-project", projectPath]
        }

        do {
            let result = try processRunner.run(
                executable: xcodebuild,
                arguments: arguments
            )

            let passed = result.succeeded
            checks.append(VerificationCheck(
                name: "build",
                description: "Project builds successfully with scheme '\(scheme)'",
                passed: passed,
                detail: passed ? nil : String(result.stderr.prefix(500))
            ))

            if !passed {
                issues.append(MigrationIssue(
                    severity: .error,
                    message: "Build failed for scheme '\(scheme)'",
                    detail: String(result.stderr.prefix(500))
                ))
            }
        } catch {
            checks.append(VerificationCheck(
                name: "build",
                description: "Project builds successfully",
                passed: false,
                detail: error.localizedDescription
            ))
            issues.append(MigrationIssue(
                severity: .error,
                message: "Failed to run xcodebuild",
                detail: error.localizedDescription
            ))
        }

        let allPassed = checks.allSatisfy { $0.passed }
        return VerificationResult(passed: allPassed, checks: checks, issues: issues)
    }
}
