// PkgLiftCore/Models/VerificationResult.swift
// Verification result models.

import Foundation

// MARK: - Verification Result

/// Result of post-migration verification.
public struct VerificationResult: Sendable, Codable {
    /// Schema version.
    public static let schemaVersion = 1

    /// The schema version.
    public let schemaVersion: Int

    /// Timestamp of verification.
    public let timestamp: Date

    /// PkgLift version.
    public let pkgLiftVersion: String

    /// Overall verification passed.
    public let passed: Bool

    /// Individual check results.
    public let checks: [VerificationCheck]

    /// Summary of issues found.
    public let issues: [MigrationIssue]

    /// All checks that passed.
    public var passedChecks: [VerificationCheck] {
        checks.filter { $0.passed }
    }

    /// All checks that failed.
    public var failedChecks: [VerificationCheck] {
        checks.filter { !$0.passed }
    }

    public init(
        passed: Bool,
        checks: [VerificationCheck],
        issues: [MigrationIssue] = []
    ) {
        self.schemaVersion = Self.schemaVersion
        self.timestamp = Date()
        self.pkgLiftVersion = PkgLiftCore.pkgLiftVersion
        self.passed = passed
        self.checks = checks
        self.issues = issues
    }
}

// MARK: - Verification Check

/// A single verification check result.
public struct VerificationCheck: Sendable, Codable {
    /// What was checked.
    public let name: String

    /// Human-readable description.
    public let description: String

    /// Whether the check passed.
    public let passed: Bool

    /// Detail about the result.
    public let detail: String?

    public init(
        name: String,
        description: String,
        passed: Bool,
        detail: String? = nil
    ) {
        self.name = name
        self.description = description
        self.passed = passed
        self.detail = detail
    }
}
