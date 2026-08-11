// PkgLiftCore/Configuration.swift
// Project configuration loading from .pkglift.yml.

import Foundation
import Yams

// MARK: - PkgLift Configuration

/// Project-level configuration loaded from `.pkglift.yml`.
///
/// PkgLift works with zero configuration. This file is optional
/// and allows teams to customize migration behavior.
public struct PkgLiftConfiguration: Sendable, Codable {
    /// Schema version.
    public let schemaVersion: Int

    /// Registry configuration.
    public let registry: RegistryConfig?

    /// Migration configuration.
    public let migration: MigrationConfig?

    /// Verification configuration.
    public let verification: VerificationConfig?

    public init(
        schemaVersion: Int = 1,
        registry: RegistryConfig? = nil,
        migration: MigrationConfig? = nil,
        verification: VerificationConfig? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.registry = registry
        self.migration = migration
        self.verification = verification
    }

    /// Default configuration when no `.pkglift.yml` exists.
    public static let `default` = PkgLiftConfiguration()
}

/// Registry configuration.
public struct RegistryConfig: Sendable, Codable {
    /// Additional registry paths to load.
    public let additionalPaths: [String]?

    public init(additionalPaths: [String]? = nil) {
        self.additionalPaths = additionalPaths
    }
}

/// Migration configuration.
public struct MigrationConfig: Sendable, Codable {
    /// Pods explicitly allowed for migration.
    public let allow: [String]?

    /// Pods explicitly denied from migration.
    public let deny: [String]?

    public init(allow: [String]? = nil, deny: [String]? = nil) {
        self.allow = allow
        self.deny = deny
    }
}

/// Verification configuration.
public struct VerificationConfig: Sendable, Codable {
    /// Whether to run build verification.
    public let build: Bool?

    public init(build: Bool? = nil) {
        self.build = build
    }
}

// MARK: - Configuration Loader

/// Loads PkgLift configuration from `.pkglift.yml`.
public struct ConfigurationLoader: Sendable {
    public init() {}

    /// Load configuration from a file path.
    ///
    /// - Parameter path: Path to `.pkglift.yml`.
    /// - Returns: Parsed configuration.
    /// - Throws: If the file cannot be read or parsed.
    public func load(from path: String) throws -> PkgLiftConfiguration {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let yamlString = String(data: data, encoding: .utf8) else {
            throw ConfigurationError.invalidEncoding(path)
        }

        let decoder = YAMLDecoder()
        let config = try decoder.decode(PkgLiftConfiguration.self, from: yamlString)

        guard config.schemaVersion == 1 else {
            throw ConfigurationError.unsupportedSchemaVersion(config.schemaVersion)
        }

        return config
    }

}

/// Configuration loading errors.
public enum ConfigurationError: Error, LocalizedError, Sendable {
    case invalidEncoding(String)
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding(let path):
            return "Configuration file is not valid UTF-8: \(path)"
        case .unsupportedSchemaVersion(let version):
            return
                "Unsupported configuration schema version: \(version). This version of PkgLift supports schema version 1."
        }
    }
}
