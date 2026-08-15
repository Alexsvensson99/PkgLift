// PkgLiftCore/Models/MigrationClassification.swift
// Migration safety classification model.

import Foundation

// MARK: - Migration Classification

/// Safety classification for a migration candidate.
///
/// PkgLift classifies every dependency into one of four categories.
/// Only `auto` dependencies may be migrated without human intervention.
///
/// ## Classification Rules
///
/// - `auto`: All conditions are deterministic and verified
/// - `review`: A likely path exists but requires developer confirmation
/// - `blocked`: Cannot currently be migrated safely
/// - `unknown`: Insufficient information to classify
public enum MigrationClassification: String, Sendable, Codable, CaseIterable {
    /// PkgLift has enough deterministic information to migrate automatically.
    case auto = "AUTO"

    /// A likely migration path exists but requires developer confirmation.
    case review = "REVIEW"

    /// The dependency cannot currently be migrated safely.
    case blocked = "BLOCKED"

    /// Insufficient information to determine migration path.
    case unknown = "UNKNOWN"

    /// The symbol used in terminal output.
    public var symbol: String {
        switch self {
        case .auto: return DiagnosticSymbol.success
        case .review: return DiagnosticSymbol.warning
        case .blocked: return DiagnosticSymbol.error
        case .unknown: return DiagnosticSymbol.unknown
        }
    }

    /// Display label for terminal output.
    public var displayLabel: String {
        return rawValue
    }
}

// MARK: - Migration Confidence

/// Confidence level for a registry mapping.
///
/// - `verified`: Confirmed from upstream official package metadata
/// - `likely`: Strong evidence but not officially confirmed
/// - `speculative`: Best-guess mapping, not suitable for auto-migration
public enum MigrationConfidence: String, Sendable, Codable, CaseIterable {
    case verified
    case likely
    case speculative
}

// MARK: - Migration Issue

/// A specific issue or risk identified during migration analysis.
public struct MigrationIssue: Sendable, Codable, Equatable {
    /// The severity of the issue.
    public let severity: Severity

    /// Human-readable description of the issue.
    public let message: String

    /// Additional detail or context.
    public let detail: String?

    /// The dependency this issue relates to, if any.
    public let dependency: String?

    public enum Severity: String, Sendable, Codable {
        case info
        case warning
        case error
    }

    public init(
        severity: Severity,
        message: String,
        detail: String? = nil,
        dependency: String? = nil
    ) {
        self.severity = severity
        self.message = message
        self.detail = detail
        self.dependency = dependency
    }
}
