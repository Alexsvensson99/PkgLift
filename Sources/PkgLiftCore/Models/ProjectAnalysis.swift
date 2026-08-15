// PkgLiftCore/Models/ProjectAnalysis.swift
// Project analysis result model.

import Foundation

// MARK: - Project Analysis

/// Complete analysis result for a project's dependency state.
///
/// This is the primary output of `pkglift analyze` and the input
/// for migration planning.
public struct ProjectAnalysis: Sendable, Codable {
    /// Schema version for JSON serialization stability.
    public static let schemaVersion = 1

    /// The schema version of this analysis.
    public let schemaVersion: Int

    /// Timestamp of the analysis.
    public let timestamp: Date

    /// PkgLift version that produced this analysis.
    public let pkgLiftVersion: String

    /// Project information.
    public let project: ProjectInfo

    /// CocoaPods dependency state.
    public let cocoaPods: CocoaPodsState

    /// Existing SwiftPM dependency state.
    public let swiftPM: SwiftPMState

    /// Migration candidates with classifications.
    public let candidates: [MigrationCandidate]

    /// Project-level risks and issues.
    public let issues: [MigrationIssue]

    /// Migration readiness score (0-100).
    public let readinessScore: Int

    /// Explicitly named dependency and artifact counts.
    ///
    /// Optional so schema-v1 artifacts produced before this additive field
    /// remain decodable.
    public let counts: DependencyCounts?

    public init(
        project: ProjectInfo,
        cocoaPods: CocoaPodsState,
        swiftPM: SwiftPMState,
        candidates: [MigrationCandidate],
        issues: [MigrationIssue],
        readinessScore: Int,
        counts: DependencyCounts? = nil
    ) {
        self.schemaVersion = Self.schemaVersion
        self.timestamp = Date()
        self.pkgLiftVersion = PkgLiftCore.pkgLiftVersion
        self.project = project
        self.cocoaPods = cocoaPods
        self.swiftPM = swiftPM
        self.candidates = candidates
        self.issues = issues
        self.readinessScore = readinessScore
        self.counts = counts
    }
}

/// Counts whose names distinguish source declarations from unique identities.
public struct DependencyCounts: Sendable, Codable, Equatable {
    public let literalPodfileDeclarationCount: Int
    public let uniqueDirectDependencyCount: Int
    public let uniqueLockfileDependencyCount: Int
    public let planEntryCount: Int
    public let analysisCandidateCount: Int

    public init(
        literalPodfileDeclarationCount: Int,
        uniqueDirectDependencyCount: Int,
        uniqueLockfileDependencyCount: Int,
        planEntryCount: Int,
        analysisCandidateCount: Int
    ) {
        self.literalPodfileDeclarationCount = literalPodfileDeclarationCount
        self.uniqueDirectDependencyCount = uniqueDirectDependencyCount
        self.uniqueLockfileDependencyCount = uniqueLockfileDependencyCount
        self.planEntryCount = planEntryCount
        self.analysisCandidateCount = analysisCandidateCount
    }
}

// MARK: - Project Info

/// Basic project metadata.
public struct ProjectInfo: Sendable, Codable {
    /// Path to the Xcode project file.
    public let projectPath: String

    /// Path to the workspace, if any.
    public let workspacePath: String?

    /// Discovered Xcode targets.
    public let targets: [TargetInfo]

    public init(
        projectPath: String,
        workspacePath: String? = nil,
        targets: [TargetInfo] = []
    ) {
        self.projectPath = projectPath
        self.workspacePath = workspacePath
        self.targets = targets
    }
}

/// Information about an Xcode target.
public struct TargetInfo: Sendable, Codable, Equatable {
    /// Target name.
    public let name: String

    /// Target type (e.g. "application", "framework", "unitTest").
    public let type: String

    /// Platform (e.g. "iOS", "macOS").
    public let platform: String?

    /// Minimum deployment target version.
    public let deploymentTarget: String?

    public init(
        name: String,
        type: String,
        platform: String? = nil,
        deploymentTarget: String? = nil
    ) {
        self.name = name
        self.type = type
        self.platform = platform
        self.deploymentTarget = deploymentTarget
    }
}

// MARK: - CocoaPods State

/// Current CocoaPods dependency state of the project.
public struct CocoaPodsState: Sendable, Codable {
    /// Literal direct dependency declarations in Podfile source order.
    public let directDependencies: [CocoaPodDependency]

    /// Transitive dependencies from Podfile.lock.
    public let transitiveDependencies: [CocoaPodDependency]

    /// Whether a Podfile was found.
    public let hasPodfile: Bool

    /// Whether a Podfile.lock was found.
    public let hasPodfileLock: Bool

    /// Whether a Pods/Manifest.lock was found.
    public let hasManifestLock: Bool

    /// Detected Podfile features/risks.
    public let podfileFeatures: PodfileFeatures

    /// Legacy row count: literal direct declarations plus transitive lockfile rows.
    ///
    /// Use `ProjectAnalysis.counts` when unique dependency identities are needed.
    public var totalDependencies: Int {
        directDependencies.count + transitiveDependencies.count
    }

    public init(
        directDependencies: [CocoaPodDependency] = [],
        transitiveDependencies: [CocoaPodDependency] = [],
        hasPodfile: Bool = false,
        hasPodfileLock: Bool = false,
        hasManifestLock: Bool = false,
        podfileFeatures: PodfileFeatures = PodfileFeatures()
    ) {
        self.directDependencies = directDependencies
        self.transitiveDependencies = transitiveDependencies
        self.hasPodfile = hasPodfile
        self.hasPodfileLock = hasPodfileLock
        self.hasManifestLock = hasManifestLock
        self.podfileFeatures = podfileFeatures
    }
}

/// Detected features and risks in the Podfile.
public struct PodfileFeatures: Sendable, Codable {
    /// Whether `use_frameworks!` is present.
    public var useFrameworks: Bool = false

    /// Whether `use_modular_headers!` is present.
    public var useModularHeaders: Bool = false

    /// Whether a `post_install` hook is present.
    public var hasPostInstallHook: Bool = false

    /// Whether a `pre_install` hook is present.
    public var hasPreInstallHook: Bool = false

    /// Whether `script_phase` is present.
    public var hasScriptPhase: Bool = false

    /// Whether dynamic Ruby logic was detected.
    public var hasDynamicRuby: Bool = false

    /// Whether `inherit! :search_paths` is present.
    public var hasInheritSearchPaths: Bool = false

    /// Whether abstract targets are used.
    public var hasAbstractTargets: Bool = false

    public init() {}

    /// Whether any migration-affecting features were detected.
    public var hasRisks: Bool {
        hasPostInstallHook || hasPreInstallHook || hasScriptPhase
            || hasDynamicRuby || useFrameworks || hasInheritSearchPaths
            || hasAbstractTargets
    }
}

// MARK: - SwiftPM State

/// Existing SwiftPM dependency state of the project.
public struct SwiftPMState: Sendable, Codable {
    /// Existing SwiftPM package dependencies.
    public let packages: [SwiftPMDependency]

    /// Whether a Package.resolved file was found.
    public let hasPackageResolved: Bool

    public init(
        packages: [SwiftPMDependency] = [],
        hasPackageResolved: Bool = false
    ) {
        self.packages = packages
        self.hasPackageResolved = hasPackageResolved
    }
}
