// PkgLiftCocoaPods/PodspecCompilationSemanticModel.swift
// Typed, analysis-only compilation and file-selection declarations.

import Foundation

/// One literal build-setting entry and its exact RFC 6901 value path.
///
/// The key and value are opaque data. PkgLift never expands macros, applies xcconfig
/// precedence, invokes a process, or projects the setting onto SwiftPM.
public struct PodspecBuildSettingDeclaration: Sendable, Equatable, Codable {
    public let key: String
    public let value: String
    public let path: String

    public init(key: String, value: String, path: String) {
        self.key = key
        self.value = value
        self.path = path
    }
}

/// One dependency's configuration whitelist as serialized by CocoaPods Core.
public struct PodspecConfigurationPodWhitelistDeclaration: Sendable, Equatable, Codable {
    public let podName: String
    public let path: String
    public let configurations: [PodspecLiteralDeclaration]

    public init(
        podName: String,
        path: String,
        configurations: [PodspecLiteralDeclaration]
    ) {
        self.podName = podName
        self.path = path
        self.configurations = configurations
    }
}

/// One explicit `requires_arc` declaration.
///
/// A boolean remains a boolean. Pattern strings remain opaque and are never expanded or
/// matched against `source_files`.
public struct PodspecARCDeclaration: Sendable, Equatable, Codable {
    public enum Value: Sendable, Equatable, Codable {
        case boolean(Bool)
        case filePatterns([PodspecLiteralDeclaration])
    }

    public let value: Value
    public let path: String

    public init(value: Value, path: String) {
        self.value = value
        self.path = path
    }
}

/// Root-only singular and plural Swift-version declarations.
///
/// `versions` contains the literal values from `swift_versions`; the declaration path
/// distinguishes an absent field from an explicit empty array. `legacySingular` preserves
/// the compatibility `swift_version` emitted by CocoaPods JSON serialization.
public struct PodspecSwiftVersionDeclarations: Sendable, Equatable, Codable {
    public enum Relationship: String, Sendable, Equatable, Codable {
        /// Zero or one representation was declared, so no cross-key comparison applies.
        case notApplicable

        /// Both keys were declared and every plural literal exactly equals the singular.
        case exactMatch

        /// Both keys were declared but require CocoaPods normalization and selection
        /// to reconcile.
        case requiresCocoaPodsNormalization
    }

    public let versions: [PodspecLiteralDeclaration]
    public let pluralDeclarationPath: String?
    public let legacySingular: PodspecLiteralDeclaration?
    public let relationship: Relationship

    public init(
        versions: [PodspecLiteralDeclaration] = [],
        pluralDeclarationPath: String? = nil,
        legacySingular: PodspecLiteralDeclaration? = nil,
        relationship: Relationship = .notApplicable
    ) {
        self.versions = versions
        self.pluralDeclarationPath = pluralDeclarationPath
        self.legacySingular = legacySingular
        self.relationship = relationship
    }

    public static let empty = PodspecSwiftVersionDeclarations()
}

/// Raw compilation and file-selection declarations made directly in one scope.
///
/// Parent, child, global, and platform values remain separate. This type never computes
/// CocoaPods inheritance, merges build settings, selects files, or claims SwiftPM
/// equivalence.
public struct PodspecCompilationDeclarations: Sendable, Equatable, Codable {
    public let compilerFlags: [PodspecLiteralDeclaration]
    public let legacyXCConfig: [PodspecBuildSettingDeclaration]
    public let podTargetXCConfig: [PodspecBuildSettingDeclaration]
    public let userTargetXCConfig: [PodspecBuildSettingDeclaration]
    public let configurationPodWhitelist: [PodspecConfigurationPodWhitelistDeclaration]
    public let swiftVersions: PodspecSwiftVersionDeclarations
    public let requiresARC: PodspecARCDeclaration?
    public let excludeFiles: [PodspecLiteralDeclaration]
    public let preservePaths: [PodspecLiteralDeclaration]

    public init(
        compilerFlags: [PodspecLiteralDeclaration] = [],
        legacyXCConfig: [PodspecBuildSettingDeclaration] = [],
        podTargetXCConfig: [PodspecBuildSettingDeclaration] = [],
        userTargetXCConfig: [PodspecBuildSettingDeclaration] = [],
        configurationPodWhitelist: [PodspecConfigurationPodWhitelistDeclaration] = [],
        swiftVersions: PodspecSwiftVersionDeclarations = .empty,
        requiresARC: PodspecARCDeclaration? = nil,
        excludeFiles: [PodspecLiteralDeclaration] = [],
        preservePaths: [PodspecLiteralDeclaration] = []
    ) {
        self.compilerFlags = compilerFlags
        self.legacyXCConfig = legacyXCConfig
        self.podTargetXCConfig = podTargetXCConfig
        self.userTargetXCConfig = userTargetXCConfig
        self.configurationPodWhitelist = configurationPodWhitelist
        self.swiftVersions = swiftVersions
        self.requiresARC = requiresARC
        self.excludeFiles = excludeFiles
        self.preservePaths = preservePaths
    }

    public static let empty = PodspecCompilationDeclarations()
}
