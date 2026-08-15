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

    public init(
        name: String,
        version: String? = nil,
        source: PodSource = .registry,
        isDirect: Bool = true,
        targets: [String] = []
    ) {
        self.name = name
        self.version = version
        self.source = source
        self.isDirect = isDirect
        self.targets = targets
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
