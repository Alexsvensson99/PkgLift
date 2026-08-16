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

    /// Confirmed project integrations that require manual migration review.
    ///
    /// Optional so older schema-1 artifacts remain decodable.
    public let detectedIntegrations: [ProjectIntegration]?

    public init(
        project: ProjectInfo,
        cocoaPods: CocoaPodsState,
        swiftPM: SwiftPMState,
        candidates: [MigrationCandidate],
        issues: [MigrationIssue],
        readinessScore: Int,
        counts: DependencyCounts? = nil,
        detectedIntegrations: [ProjectIntegration]? = nil
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
        self.detectedIntegrations = detectedIntegrations.map {
            Array(Set($0)).sorted()
        }
    }
}

/// Confirmed dependency-system or generated-project integration.
public enum ProjectIntegration: String, Sendable, Codable, CaseIterable, Comparable {
    case carthage
    case reactNative
    case flutter
    case capacitor

    public static func < (lhs: ProjectIntegration, rhs: ProjectIntegration) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .carthage: 0
        case .reactNative: 1
        case .flutter: 2
        case .capacitor: 3
        }
    }

    public var reviewReason: String {
        switch self {
        case .carthage:
            "Carthage integration detected"
        case .reactNative:
            "React Native Podfile integration marker detected"
        case .flutter:
            "Flutter Podfile integration marker detected"
        case .capacitor:
            "Capacitor Podfile integration marker detected"
        }
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

/// Source languages compiled by an Xcode target.
public enum SourceLanguage: String, Sendable, Codable, CaseIterable, Comparable {
    case swift
    case objectiveC
    case objectiveCPlusPlus
    case c
    case cPlusPlus

    public static func < (lhs: SourceLanguage, rhs: SourceLanguage) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .swift: 0
        case .objectiveC: 1
        case .objectiveCPlusPlus: 2
        case .c: 3
        case .cPlusPlus: 4
        }
    }
}

/// Whether PBX metadata completely describes a target's compiled sources.
public enum SourceProfileCompleteness: String, Sendable, Codable {
    case complete
    case incomplete
}

/// Deterministic source-language evidence derived only from PBX metadata.
public struct TargetSourceProfile: Sendable, Codable, Equatable {
    public let languages: [SourceLanguage]
    public let completeness: SourceProfileCompleteness

    public init(
        languages: [SourceLanguage],
        completeness: SourceProfileCompleteness
    ) {
        self.languages = Array(Set(languages)).sorted()
        self.completeness = completeness
    }

    private enum CodingKeys: String, CodingKey {
        case languages
        case completeness
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            languages: try container.decode([SourceLanguage].self, forKey: .languages),
            completeness: try container.decode(SourceProfileCompleteness.self, forKey: .completeness)
        )
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

    /// PBX-derived source-language evidence, when produced by a compatible analyzer.
    public let sourceProfile: TargetSourceProfile?

    public init(
        name: String,
        type: String,
        platform: String? = nil,
        deploymentTarget: String? = nil,
        sourceProfile: TargetSourceProfile? = nil
    ) {
        self.name = name
        self.type = type
        self.platform = platform
        self.deploymentTarget = deploymentTarget
        self.sourceProfile = sourceProfile
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

    /// Typed generated-project or cross-platform integration markers.
    public var integrationMarkers: [ProjectIntegration] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case useFrameworks
        case useModularHeaders
        case hasPostInstallHook
        case hasPreInstallHook
        case hasScriptPhase
        case hasDynamicRuby
        case hasInheritSearchPaths
        case hasAbstractTargets
        case integrationMarkers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        useFrameworks = try container.decodeIfPresent(Bool.self, forKey: .useFrameworks) ?? false
        useModularHeaders = try container.decodeIfPresent(Bool.self, forKey: .useModularHeaders) ?? false
        hasPostInstallHook = try container.decodeIfPresent(Bool.self, forKey: .hasPostInstallHook) ?? false
        hasPreInstallHook = try container.decodeIfPresent(Bool.self, forKey: .hasPreInstallHook) ?? false
        hasScriptPhase = try container.decodeIfPresent(Bool.self, forKey: .hasScriptPhase) ?? false
        hasDynamicRuby = try container.decodeIfPresent(Bool.self, forKey: .hasDynamicRuby) ?? false
        hasInheritSearchPaths = try container.decodeIfPresent(Bool.self, forKey: .hasInheritSearchPaths) ?? false
        hasAbstractTargets = try container.decodeIfPresent(Bool.self, forKey: .hasAbstractTargets) ?? false
        integrationMarkers = Array(Set(
            try container.decodeIfPresent(
                [ProjectIntegration].self,
                forKey: .integrationMarkers
            ) ?? []
        )).sorted()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(useFrameworks, forKey: .useFrameworks)
        try container.encode(useModularHeaders, forKey: .useModularHeaders)
        try container.encode(hasPostInstallHook, forKey: .hasPostInstallHook)
        try container.encode(hasPreInstallHook, forKey: .hasPreInstallHook)
        try container.encode(hasScriptPhase, forKey: .hasScriptPhase)
        try container.encode(hasDynamicRuby, forKey: .hasDynamicRuby)
        try container.encode(hasInheritSearchPaths, forKey: .hasInheritSearchPaths)
        try container.encode(hasAbstractTargets, forKey: .hasAbstractTargets)
        try container.encode(Array(Set(integrationMarkers)).sorted(), forKey: .integrationMarkers)
    }

    /// Whether any migration-affecting features were detected.
    public var hasRisks: Bool {
        hasPostInstallHook || hasPreInstallHook || hasScriptPhase
            || hasDynamicRuby || useFrameworks || hasInheritSearchPaths
            || hasAbstractTargets || !integrationMarkers.isEmpty
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
