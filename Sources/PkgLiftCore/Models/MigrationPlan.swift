// PkgLiftCore/Models/MigrationPlan.swift
// Migration plan models.

import Foundation

// MARK: - Migration Candidate

/// A single dependency evaluated for migration.
public struct MigrationCandidate: Sendable, Codable {
    /// The CocoaPod being evaluated.
    public let pod: CocoaPodDependency

    /// The migration classification.
    public let classification: MigrationClassification

    /// The proposed SwiftPM package, if a mapping exists.
    public let packageCandidate: PackageCandidate?

    /// Reasons for the classification.
    public let reasons: [String]

    /// Stable machine-readable classification reasons with optional guidance.
    ///
    /// Optional so schema-1 artifacts produced before this additive field
    /// remain decodable. This field is reporting metadata, not executable
    /// migration evidence.
    public let reasonDetails: [MigrationReason]?

    /// Issues specific to this candidate.
    public let issues: [MigrationIssue]

    public init(
        pod: CocoaPodDependency,
        classification: MigrationClassification,
        packageCandidate: PackageCandidate? = nil,
        reasons: [String] = [],
        reasonDetails: [MigrationReason]? = nil,
        issues: [MigrationIssue] = []
    ) {
        self.pod = pod
        self.classification = classification
        self.packageCandidate = packageCandidate
        self.reasons = reasons
        self.reasonDetails = reasonDetails
        self.issues = issues
    }
}

// MARK: - Package Candidate

/// A proposed SwiftPM package to replace a CocoaPod.
public struct PackageCandidate: Sendable, Codable, Equatable {
    /// The SwiftPM package repository URL.
    public let repositoryURL: String

    /// The SwiftPM product names to link.
    public let products: [String]

    /// The proposed version requirement.
    public let versionRequirement: SwiftPMVersionRequirement?

    /// The confidence level of this mapping.
    public let confidence: MigrationConfidence

    /// Consumer languages explicitly supported by the registry mapping.
    ///
    /// Optional for schema-1 backward decoding. Missing evidence is never
    /// sufficient for automatic migration.
    public let supportedConsumerLanguages: [SourceLanguage]?

    public init(
        repositoryURL: String,
        products: [String],
        versionRequirement: SwiftPMVersionRequirement? = nil,
        confidence: MigrationConfidence = .verified,
        supportedConsumerLanguages: [SourceLanguage]? = nil
    ) {
        self.repositoryURL = repositoryURL
        self.products = products
        self.versionRequirement = versionRequirement
        self.confidence = confidence
        self.supportedConsumerLanguages = supportedConsumerLanguages
    }
}

// MARK: - Migration Plan

/// A complete migration plan for a project.
///
/// Written to `.pkglift/plan.json` and consumed by the migration engine.
/// Plans are reproducible artifacts—given the same inputs, PkgLift
/// produces the same plan.
public struct MigrationPlan: Sendable, Codable {
    /// Schema version for forward compatibility.
    public static let schemaVersion = 1

    /// The schema version of this plan.
    public let schemaVersion: Int

    /// Timestamp when the plan was generated.
    public let timestamp: Date

    /// PkgLift version that produced this plan.
    public let pkgLiftVersion: String

    /// Project path.
    public let projectPath: String

    /// Individual migration entries.
    public let entries: [MigrationPlanEntry]

    /// Project-level issues.
    public let issues: [MigrationIssue]

    /// Migration readiness score (0-100).
    public let readinessScore: Int

    /// Explicit source, dependency, candidate, and plan-entry counts.
    public let counts: DependencyCounts?

    /// Entries that can be automatically migrated.
    public var autoEntries: [MigrationPlanEntry] {
        entries.filter { $0.classification == .auto }
    }

    /// Entries requiring review.
    public var reviewEntries: [MigrationPlanEntry] {
        entries.filter { $0.classification == .review }
    }

    /// Blocked entries.
    public var blockedEntries: [MigrationPlanEntry] {
        entries.filter { $0.classification == .blocked }
    }

    /// Unknown entries.
    public var unknownEntries: [MigrationPlanEntry] {
        entries.filter { $0.classification == .unknown }
    }

    public init(
        projectPath: String,
        entries: [MigrationPlanEntry],
        issues: [MigrationIssue],
        readinessScore: Int,
        counts: DependencyCounts? = nil
    ) {
        self.schemaVersion = Self.schemaVersion
        self.timestamp = Date()
        self.pkgLiftVersion = PkgLiftCore.pkgLiftVersion
        self.projectPath = projectPath
        self.entries = entries
        self.issues = issues
        self.readinessScore = readinessScore
        self.counts = counts
    }
}

// MARK: - Migration Plan Entry

/// A single entry in the migration plan.
public struct MigrationPlanEntry: Sendable, Codable {
    /// The pod to migrate.
    public let podName: String

    /// The resolved version from Podfile.lock.
    public let currentVersion: String?

    /// Credential-free external-source evidence captured when planning.
    ///
    /// Optional for backward decoding. External provenance is reporting and
    /// preflight evidence only; it never enables automatic migration in v0.4.
    public let sourceProvenance: DependencySourceProvenance?

    /// The migration classification.
    public let classification: MigrationClassification

    /// The proposed actions.
    public let actions: [MigrationAction]

    /// Reasons for the classification.
    public let reasons: [String]

    /// Stable machine-readable classification reasons with optional guidance.
    /// Optional for backward decoding and deliberately excluded from the
    /// executable preflight contract.
    public let reasonDetails: [MigrationReason]?

    /// The target Xcode target for the new dependency.
    public let targetName: String?

    /// The proposed SwiftPM package.
    public let packageCandidate: PackageCandidate?

    /// Literal declaration origins represented by this entry.
    public let declarations: [PodfileDeclaration]?

    /// Explicit static target evidence represented by this entry.
    public let targetAttribution: TargetAttribution?

    /// PBX-derived language evidence for the destination target.
    public let targetSourceProfile: TargetSourceProfile?

    public init(
        podName: String,
        currentVersion: String? = nil,
        sourceProvenance: DependencySourceProvenance? = nil,
        classification: MigrationClassification,
        actions: [MigrationAction] = [],
        reasons: [String] = [],
        reasonDetails: [MigrationReason]? = nil,
        targetName: String? = nil,
        packageCandidate: PackageCandidate? = nil,
        declarations: [PodfileDeclaration]? = nil,
        targetAttribution: TargetAttribution? = nil,
        targetSourceProfile: TargetSourceProfile? = nil
    ) {
        self.podName = podName
        self.currentVersion = currentVersion
        self.sourceProvenance = sourceProvenance
        self.classification = classification
        self.actions = actions
        self.reasons = reasons
        self.reasonDetails = reasonDetails
        self.targetName = targetName
        self.packageCandidate = packageCandidate
        self.declarations = declarations
        self.targetAttribution = targetAttribution
        self.targetSourceProfile = targetSourceProfile
    }
}

// MARK: - Migration Action

/// A discrete action to perform during migration.
public enum MigrationAction: Sendable, Codable, Equatable {
    /// Remove a pod from the Podfile.
    case removePod(name: String)

    /// Add a SwiftPM package reference to the Xcode project.
    case addSwiftPackage(repositoryURL: String, requirement: SwiftPMVersionRequirement)

    /// Link a product from a specific SwiftPM package to an Xcode target.
    case linkProduct(repositoryURL: String, productName: String, targetName: String)

    /// Manual action required (with instructions).
    case manual(description: String)
}
