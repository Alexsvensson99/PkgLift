// PkgLiftCore/Models/RegistryMapping.swift
// Registry mapping model for CocoaPod → SwiftPM mappings.

import Foundation

// MARK: - Registry Mapping

/// A mapping from a CocoaPod to its SwiftPM equivalent.
///
/// Registry mappings are the core of PkgLift's deterministic
/// migration engine. Each mapping represents a verified relationship
/// between a CocoaPod and an official SwiftPM package.
///
/// ## Schema Versioning
///
/// The `schemaVersion` field ensures forward compatibility.
/// Clients should reject mappings with unsupported schema versions
/// rather than silently misinterpreting them.
public struct RegistryMapping: Sendable, Codable, Equatable {
    /// Schema version of this mapping file.
    public let schemaVersion: Int

    /// The source CocoaPod.
    public let pod: PodIdentifier

    /// The target SwiftPM package.
    public let swiftpm: SwiftPMPackageInfo

    /// Migration metadata.
    public let migration: MigrationInfo

    /// Optional metadata.
    public let metadata: MappingMetadata?

    public init(
        schemaVersion: Int = 1,
        pod: PodIdentifier,
        swiftpm: SwiftPMPackageInfo,
        migration: MigrationInfo,
        metadata: MappingMetadata? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.pod = pod
        self.swiftpm = swiftpm
        self.migration = migration
        self.metadata = metadata
    }
}

// MARK: - Pod Identifier

/// Identifies a CocoaPod, optionally with a specific subspec.
public struct PodIdentifier: Sendable, Codable, Equatable {
    /// The pod name (e.g. "Firebase").
    public let name: String

    /// The subspec, if this mapping is for a specific subspec (e.g. "Analytics").
    public let subspec: String?

    /// The full pod specification name.
    public var fullName: String {
        if let subspec = subspec {
            return "\(name)/\(subspec)"
        }
        return name
    }

    public init(name: String, subspec: String? = nil) {
        self.name = name
        self.subspec = subspec
    }
}

// MARK: - SwiftPM Package Info

/// Information about the target SwiftPM package.
public struct SwiftPMPackageInfo: Sendable, Codable, Equatable {
    /// The package repository URL.
    public let repository: String

    /// The product names to link.
    public let products: [String]

    /// Minimum version, if known.
    public let minimumVersion: String?

    /// Consumer source languages verified for the mapped SwiftPM products.
    ///
    /// Optional so existing external schema-1 mappings remain decodable. A
    /// missing value is absence of evidence and must not be treated as support.
    public let supportedConsumerLanguages: [SourceLanguage]?

    public init(
        repository: String,
        products: [String],
        minimumVersion: String? = nil,
        supportedConsumerLanguages: [SourceLanguage]? = nil
    ) {
        self.repository = repository
        self.products = products
        self.minimumVersion = minimumVersion
        self.supportedConsumerLanguages = supportedConsumerLanguages
    }
}

// MARK: - Migration Info

/// Migration-specific metadata for a registry mapping.
public struct MigrationInfo: Sendable, Codable, Equatable {
    /// Confidence level of the mapping.
    public let confidence: MigrationConfidence

    /// Optional notes about migration considerations.
    public let notes: String?

    public init(confidence: MigrationConfidence, notes: String? = nil) {
        self.confidence = confidence
        self.notes = notes
    }
}

// MARK: - Mapping Metadata

/// Optional metadata for a registry mapping.
public struct MappingMetadata: Sendable, Codable, Equatable {
    /// Human-readable notes.
    public let notes: String?

    /// Who contributed this mapping.
    public let contributor: String?

    /// When this mapping was last verified.
    public let lastVerified: String?

    public init(
        notes: String? = nil,
        contributor: String? = nil,
        lastVerified: String? = nil
    ) {
        self.notes = notes
        self.contributor = contributor
        self.lastVerified = lastVerified
    }
}
