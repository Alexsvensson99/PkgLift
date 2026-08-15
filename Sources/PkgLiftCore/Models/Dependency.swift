// PkgLiftCore/Models/Dependency.swift
// Strongly typed dependency models for CocoaPods and SwiftPM.

import Foundation

// MARK: - CocoaPod Dependency

/// Represents a resolved CocoaPods dependency.
public struct CocoaPodDependency: Sendable, Codable, Equatable {
    /// The pod name (e.g. "Alamofire" or "Firebase/Analytics").
    public let name: String

    /// The base pod name without subspec (e.g. "Firebase" for "Firebase/Analytics").
    public var baseName: String {
        if let slashIndex = name.firstIndex(of: "/") {
            return String(name[name.startIndex..<slashIndex])
        }
        return name
    }

    /// The subspec name, if any (e.g. "Analytics" for "Firebase/Analytics").
    public var subspecName: String? {
        guard let slashIndex = name.firstIndex(of: "/") else { return nil }
        return String(name[name.index(after: slashIndex)...])
    }

    /// Whether this pod has a subspec.
    public var isSubspec: Bool {
        return name.contains("/")
    }

    /// The resolved version from Podfile.lock.
    public let version: String?

    /// How this dependency was declared.
    public let source: PodSource

    /// Whether this is a direct dependency (declared in Podfile)
    /// or a transitive dependency.
    public let isDirect: Bool

    /// The targets this pod is linked to, when deterministically known.
    public let targets: [String]

    /// Literal Podfile declarations that contributed to this dependency.
    ///
    /// This additive field is absent when older analysis artifacts are decoded.
    public let declarations: [PodfileDeclaration]?

    /// Static target evidence for this dependency.
    ///
    /// `targets` is retained for schema compatibility. This field explains
    /// whether those targets are exact, multiple, partial, or unresolved.
    public let targetAttribution: TargetAttribution?

    public init(
        name: String,
        version: String? = nil,
        source: PodSource = .registry,
        isDirect: Bool = true,
        targets: [String] = [],
        declarations: [PodfileDeclaration]? = nil,
        targetAttribution: TargetAttribution? = nil
    ) {
        self.name = name
        self.version = version
        self.source = source
        self.isDirect = isDirect
        self.targets = targets
        self.declarations = declarations
        self.targetAttribution = targetAttribution
    }

    /// Target evidence with a fail-closed compatibility fallback.
    ///
    /// Legacy artifacts contain target names but no source declarations, so
    /// they can never prove exact AUTO eligibility. The names remain visible
    /// as partial context while migration requires regenerated evidence.
    public var effectiveTargetAttribution: TargetAttribution {
        targetAttribution ?? TargetAttribution.legacyFallback(
            from: targets,
            isDirect: isDirect
        )
    }

    /// Whether this dependency carries enough source evidence for AUTO.
    public var hasLiteralMigrationProvenance: Bool {
        guard let targetAttribution,
              targetAttribution.status == .exact,
              targetAttribution.targets.count == 1,
              targetAttribution.unresolvedDeclarationCount == 0,
              let targetName = targetAttribution.targets.first,
              let declarations,
              !declarations.isEmpty else {
            return false
        }
        return declarations.allSatisfy {
            $0.targetName == targetName && $0.isEligibleForAutomaticMigration
        }
    }
}

// MARK: - Podfile Declaration Evidence

/// The static Podfile scope that contains a literal `pod` declaration.
public enum PodfileDeclarationScope: String, Sendable, Codable, Equatable {
    case topLevel
    case target
    case rubyHelper
    case abstractTarget
    case dynamicScope
}

/// Source-level evidence for one literal Podfile declaration.
public struct PodfileDeclaration: Sendable, Codable, Equatable {
    /// One-based Podfile line number.
    public let line: Int

    /// The statically recognized declaration scope.
    public let scope: PodfileDeclarationScope

    /// Target, helper, or abstract-target name associated with the scope.
    public let scopeName: String?

    /// A proven literal Xcode target name, when one exists.
    public let targetName: String?

    /// Source syntax attached to this exact declaration.
    public let source: PodSource

    public init(
        line: Int,
        scope: PodfileDeclarationScope,
        scopeName: String? = nil,
        targetName: String? = nil,
        source: PodSource = .registry
    ) {
        self.line = line
        self.scope = scope
        self.scopeName = scopeName
        self.targetName = targetName
        self.source = source
    }

    /// Whether this source origin can support an automatic migration.
    ///
    /// Top-level, abstract-target, and dynamic scopes cannot prove one Xcode
    /// destination. Direct target declarations must agree with their scope;
    /// statically resolved helpers must retain a literal helper name.
    public var isEligibleForAutomaticMigration: Bool {
        guard line > 0,
              source == .registry,
              let targetName,
              !targetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        switch scope {
        case .target:
            return scopeName == targetName
        case .rubyHelper:
            guard let scopeName else { return false }
            return !scopeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .topLevel, .abstractTarget, .dynamicScope:
            return false
        }
    }
}

/// How completely static Podfile structure proves destination targets.
public enum TargetAttributionStatus: String, Sendable, Codable, Equatable {
    /// Every declaration resolves to the same single literal target.
    case exact

    /// Every declaration is resolved, across more than one literal target.
    case multiple

    /// Some declaration targets are proven and some remain unresolved.
    case partial

    /// No destination target is proven.
    case unresolved
}

/// Explicit target evidence for a dependency or plan entry.
public struct TargetAttribution: Sendable, Codable, Equatable {
    public let status: TargetAttributionStatus
    public let targets: [String]
    public let unresolvedDeclarationCount: Int
    public let reason: String?

    public init(
        status: TargetAttributionStatus,
        targets: [String] = [],
        unresolvedDeclarationCount: Int = 0,
        reason: String? = nil
    ) {
        self.status = status
        self.targets = Array(Set(targets)).sorted()
        self.unresolvedDeclarationCount = unresolvedDeclarationCount
        self.reason = reason
    }

    /// Fail-closed interpretation of schema-legacy target arrays.
    public static func legacyFallback(
        from targets: [String],
        isDirect: Bool
    ) -> TargetAttribution {
        let uniqueTargets = Array(Set(targets)).sorted()
        if isDirect, !uniqueTargets.isEmpty {
            return TargetAttribution(
                status: .partial,
                targets: uniqueTargets,
                unresolvedDeclarationCount: 1,
                reason: "Legacy target names lack literal Podfile declaration provenance."
            )
        }
        return TargetAttribution(
            status: .unresolved,
            unresolvedDeclarationCount: isDirect ? 1 : 0,
            reason: isDirect
                ? "No destination target is proven from static Podfile structure."
                : "Transitive lockfile dependency has no literal Podfile declaration."
        )
    }
}

// MARK: - Pod Source

/// How a CocoaPod dependency is sourced.
public enum PodSource: Sendable, Codable, Equatable {
    /// Standard spec repository (default).
    case registry

    /// Git repository with optional ref.
    case git(url: String, ref: GitRef?)

    /// Local path dependency.
    case path(String)

    /// Unknown or unparseable source.
    case unknown
}

/// A Git reference for an external pod source.
public enum GitRef: Sendable, Codable, Equatable {
    case branch(String)
    case tag(String)
    case commit(String)
}

// MARK: - SwiftPM Dependency

/// Represents an existing SwiftPM package dependency in an Xcode project.
public struct SwiftPMDependency: Sendable, Codable, Equatable {
    /// The package repository URL.
    public let repositoryURL: String

    /// The version requirement, if any.
    public let requirement: SwiftPMVersionRequirement?

    /// Products from this package that are linked to targets.
    public let linkedProducts: [LinkedProduct]

    public init(
        repositoryURL: String,
        requirement: SwiftPMVersionRequirement? = nil,
        linkedProducts: [LinkedProduct] = []
    ) {
        self.repositoryURL = repositoryURL
        self.requirement = requirement
        self.linkedProducts = linkedProducts
    }
}

/// A SwiftPM product linked to a specific target.
public struct LinkedProduct: Sendable, Codable, Equatable {
    /// The product name.
    public let productName: String

    /// The target it is linked to.
    public let targetName: String

    public init(productName: String, targetName: String) {
        self.productName = productName
        self.targetName = targetName
    }
}

// MARK: - SwiftPM Version Requirement

/// Version requirement for a SwiftPM package.
public enum SwiftPMVersionRequirement: Sendable, Codable, Equatable {
    /// Minimum version (from: "x.y.z").
    case from(String)

    /// Next-minor requirement (up to, but excluding, the next minor version).
    case upToNextMinor(String)

    /// Exact version.
    case exact(String)

    /// Version range.
    case range(from: String, to: String)

    /// Branch-based requirement.
    case branch(String)

    /// Revision-based requirement.
    case revision(String)
}
