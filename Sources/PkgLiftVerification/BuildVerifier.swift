// PkgLiftVerification/BuildVerifier.swift
// Optional build verification using xcodebuild.

import Foundation
import PkgLiftCore

/// Verifies a project builds correctly after migration.
public struct BuildVerifier: Sendable {
    private let processRunner: ProcessRunner

    public init(processRunner: ProcessRunner = ProcessRunner()) {
        self.processRunner = processRunner
    }

    /// Normalizes and validates an explicitly selected scheme.
    public static func validatedScheme(_ value: String) throws -> String {
        if value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            throw BuildVerificationOptionsError.controlCharacter(field: "scheme")
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw BuildVerificationOptionsError.empty(field: "scheme")
        }
        return normalized
    }

    /// Creates the exact argument vector used for package resolution.
    ///
    /// Configuration, destination, and SDK are build-only settings. The selected
    /// scheme is still passed because Xcode requires it for workspace resolution
    /// and whenever a derived-data path is supplied.
    public static func resolvePackageArguments(
        projectPath: String,
        scheme: String? = nil,
        isWorkspace: Bool = false,
        options: BuildVerificationOptions = BuildVerificationOptions()
    ) throws -> [String] {
        let options = try options.validated()
        let validatedScheme = try scheme.map(validatedScheme)

        if isWorkspace && validatedScheme == nil {
            throw BuildVerificationOptionsError.schemeRequiredForWorkspaceResolution
        }
        if options.derivedDataPath != nil && validatedScheme == nil {
            throw BuildVerificationOptionsError.schemeRequiredForDerivedDataResolution
        }

        var arguments = ["-resolvePackageDependencies"]
        if isWorkspace {
            arguments += ["-workspace", projectPath]
        } else {
            arguments += ["-project", projectPath]
        }
        if let validatedScheme {
            arguments += ["-scheme", validatedScheme]
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
        let scheme = try validatedScheme(scheme)
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
    public func resolvePackageDependencies(
        projectPath: String,
        scheme: String? = nil,
        isWorkspace: Bool = false,
        options: BuildVerificationOptions = BuildVerificationOptions()
    ) -> VerificationResult {
        var checks: [VerificationCheck] = []
        var issues: [MigrationIssue] = []

        let arguments: [String]
        do {
            arguments = try Self.resolvePackageArguments(
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
                message: "Invalid package-resolution options",
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
            let result = try processRunner.run(executable: xcodebuild, arguments: arguments)
            checks.append(VerificationCheck(
                name: "resolve_dependencies",
                description: "SwiftPM package dependencies resolve successfully",
                passed: result.succeeded,
                detail: result.succeeded ? nil : result.stderr
            ))
            if !result.succeeded {
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

        return VerificationResult(
            passed: checks.allSatisfy(\.passed),
            checks: checks,
            issues: issues
        )
    }

    /// Runs a full build verification.
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
            let result = try processRunner.run(executable: xcodebuild, arguments: arguments)
            checks.append(VerificationCheck(
                name: "build",
                description: "Project builds successfully with scheme '\(scheme)'",
                passed: result.succeeded,
                detail: result.succeeded ? nil : String(result.stderr.prefix(500))
            ))
            if !result.succeeded {
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

        return VerificationResult(
            passed: checks.allSatisfy(\.passed),
            checks: checks,
            issues: issues
        )
    }
}
