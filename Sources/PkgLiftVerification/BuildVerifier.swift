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

    /// Creates the exact argument vector used for package resolution.
    ///
    /// Only the derived-data path applies to this phase. Configuration,
    /// destination, and SDK are build settings and are intentionally omitted.
    public static func resolvePackageArguments(
        projectPath: String,
        isWorkspace: Bool = false,
        options: BuildVerificationOptions = BuildVerificationOptions()
    ) throws -> [String] {
        let options = try options.validated()
        var arguments = ["-resolvePackageDependencies"]

        if isWorkspace {
            arguments += ["-workspace", projectPath]
        } else {
            arguments += ["-project", projectPath]
        }

        if let derivedDataPath = options.derivedDataPath {
            arguments += ["-derivedDataPath", derivedDataPath]
        }
        return arguments
    }

    /// Creates the exact argument vector used for full build verification.
    public static func buildArguments(
        projectPath: String,
        scheme: String,
        isWorkspace: Bool = false,
        options: BuildVerificationOptions = BuildVerificationOptions()
    ) throws -> [String] {
        let scheme = try normalizedScheme(scheme)
        let options = try options.validated()

        var arguments = ["build", "-scheme", scheme]
        if isWorkspace {
            arguments += ["-workspace", projectPath]
        } else {
            arguments += ["-project", projectPath]
        }

        if let configuration = options.configuration {
            arguments += ["-configuration", configuration]
        }
        if let destination = options.destination {
            arguments += ["-destination", destination]
        }
        if let sdk = options.sdk {
            arguments += ["-sdk", sdk]
        }
        if let derivedDataPath = options.derivedDataPath {
            arguments += ["-derivedDataPath", derivedDataPath]
        }
        return arguments
    }

    /// Resolves SwiftPM package dependencies.
    ///
    /// - Parameters:
    ///   - projectPath: Path to `.xcodeproj` or `.xcworkspace`.
    ///   - isWorkspace: Whether the path is a workspace.
    ///   - options: Explicit verification options. Only derived data applies.
    /// - Returns: A `VerificationResult`.
    public func resolvePackageDependencies(
        projectPath: String,
        isWorkspace: Bool = false,
        options: BuildVerificationOptions = BuildVerificationOptions()
    ) -> VerificationResult {
        var checks: [VerificationCheck] = []
        var issues: [MigrationIssue] = []

        let arguments: [String]
        do {
            arguments = try Self.resolvePackageArguments(
                projectPath: projectPath,
                isWorkspace: isWorkspace,
                options: options
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
            return VerificationResult(passed: false, checks: checks, issues: issues)
        }

        guard let xcodebuild = processRunner.findExecutable("xcodebuild") else {
            checks.append(VerificationCheck(
                name: "xcodebuild_available",
                description: "xcodebuild is available",
                passed: false,
                detail: "xcodebuild not found in PATH. Install Xcode Command Line Tools."
            ))
            return VerificationResult(passed: false, checks: checks, issues: issues)
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
    ///   - scheme: The scheme to build. Required rather than guessed.
    ///   - isWorkspace: Whether the path is a workspace.
    ///   - options: Explicit xcodebuild configuration and destination settings.
    /// - Returns: A `VerificationResult`.
    public func buildVerify(
        projectPath: String,
        scheme: String?,
        isWorkspace: Bool = false,
        options: BuildVerificationOptions = BuildVerificationOptions()
    ) -> VerificationResult {
        var checks: [VerificationCheck] = []
        var issues: [MigrationIssue] = []

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
            return VerificationResult(passed: false, checks: checks, issues: issues)
        }

        let arguments: [String]
        do {
            arguments = try Self.buildArguments(
                projectPath: projectPath,
                scheme: scheme,
                isWorkspace: isWorkspace,
                options: options
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
            return VerificationResult(passed: false, checks: checks, issues: issues)
        }

        guard let xcodebuild = processRunner.findExecutable("xcodebuild") else {
            checks.append(VerificationCheck(
                name: "xcodebuild_available",
                description: "xcodebuild is available",
                passed: false,
                detail: "xcodebuild not found in PATH"
            ))
            return VerificationResult(passed: false, checks: checks, issues: issues)
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

    private static func normalizedScheme(_ value: String) throws -> String {
        if value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            throw BuildVerificationOptionsError.controlCharacter(field: "scheme")
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw BuildVerificationOptionsError.empty(field: "scheme")
        }
        return normalized
    }
}
