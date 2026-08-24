// PkgLiftCocoaPods/PodspecSemanticModel.swift
// Typed, analysis-only representation of bounded Podspec JSON semantics.

import Foundation

/// The CocoaPods Core semantics used to interpret a Podspec JSON document.
///
/// Podspec JSON has no embedded schema or generator version. Callers therefore select a
/// profile explicitly, and the inspector rejects every profile it does not implement.
public struct CocoaPodsSemanticProfile: Sendable, Hashable, Codable, RawRepresentable {
    public let rawValue: String

    public var identifier: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(identifier: String) {
        self.init(rawValue: identifier)
    }

    /// CocoaPods Core 1.17.0, tag commit `f14b9a21f3aacd771c1eb9b099910d33a6d2cce0`.
    public static let cocoaPodsCore1_17_0 = CocoaPodsSemanticProfile(
        rawValue: "cocoapods-core/1.17.0"
    )

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The bounded semantic subset extracted from an already available Podspec JSON document.
///
/// The recursive `root` tree is authoritative. The flat properties are compatibility
/// projections of the root's global declarations. This model describes declarations only;
/// it is not evidence that a pod can be represented by SwiftPM and it does not affect
/// migration classification or AUTO eligibility.
public struct PodspecSemanticModel: Sendable, Equatable, Codable {
    public let semanticProfile: CocoaPodsSemanticProfile
    public let version: String
    public let root: PodspecNode

    public var name: String { root.name }
    public var platforms: [PodspecPlatformRequirement] { root.platforms }
    public var sourceFiles: [String] { root.declarations.sourceFiles }
    public var publicHeaders: [String] { root.declarations.publicHeaders }
    public var privateHeaders: [String] { root.declarations.privateHeaders }
    public var resources: [String] { root.declarations.resources }
    public var resourceBundles: [PodspecResourceBundle] {
        root.declarations.resourceBundles
    }

    public init(
        semanticProfile: CocoaPodsSemanticProfile = .cocoaPodsCore1_17_0,
        version: String,
        root: PodspecNode
    ) {
        self.semanticProfile = semanticProfile
        self.version = version
        self.root = root
    }

    /// Compatibility initializer for the original flat, root-only model.
    public init(
        name: String,
        version: String,
        platforms: [PodspecPlatformRequirement],
        sourceFiles: [String],
        publicHeaders: [String],
        privateHeaders: [String],
        resources: [String],
        resourceBundles: [PodspecResourceBundle]
    ) {
        self.init(
            version: version,
            root: PodspecNode(
                name: name,
                baseName: name,
                path: "",
                platforms: platforms,
                declarations: PodspecScopedDeclarations(
                    sourceFiles: sourceFiles,
                    publicHeaders: publicHeaders,
                    privateHeaders: privateHeaders,
                    resources: resources,
                    resourceBundles: resourceBundles,
                    dependencies: []
                ),
                platformScopes: [],
                defaultSubspecs: .implicitAll,
                subspecs: []
            )
        )
    }
}

/// One root or library-subspec node in the declared Podspec hierarchy.
///
/// `name` is the complete CocoaPods identity (`Root/Child/Leaf`), `baseName` is the
/// node-local declaration, and `path` identifies the node object in the source JSON.
public struct PodspecNode: Sendable, Equatable, Codable {
    public let name: String
    public let baseName: String
    public let path: String
    public let platforms: [PodspecPlatformRequirement]
    public let declarations: PodspecScopedDeclarations
    public let platformScopes: [PodspecPlatformScope]
    public let defaultSubspecs: PodspecDefaultSubspecSelection
    public let subspecs: [PodspecNode]

    public init(
        name: String,
        baseName: String,
        path: String,
        platforms: [PodspecPlatformRequirement],
        declarations: PodspecScopedDeclarations,
        platformScopes: [PodspecPlatformScope],
        defaultSubspecs: PodspecDefaultSubspecSelection,
        subspecs: [PodspecNode]
    ) {
        self.name = name
        self.baseName = baseName
        self.path = path
        self.platforms = platforms
        self.declarations = declarations
        self.platformScopes = platformScopes
        self.defaultSubspecs = defaultSubspecs
        self.subspecs = subspecs
    }
}

/// Raw declarations made directly in one root, subspec, or platform scope.
///
/// Values from parents, children, global scopes, and platform scopes are never merged here.
public struct PodspecScopedDeclarations: Sendable, Equatable, Codable {
    public let sourceFiles: [String]
    public let publicHeaders: [String]
    public let privateHeaders: [String]
    public let resources: [String]
    public let resourceBundles: [PodspecResourceBundle]
    public let dependencies: [PodspecDependencyDeclaration]
    public let linkage: PodspecLinkageDeclarations

    public init(
        sourceFiles: [String] = [],
        publicHeaders: [String] = [],
        privateHeaders: [String] = [],
        resources: [String] = [],
        resourceBundles: [PodspecResourceBundle] = [],
        dependencies: [PodspecDependencyDeclaration] = [],
        linkage: PodspecLinkageDeclarations = .empty
    ) {
        self.sourceFiles = sourceFiles
        self.publicHeaders = publicHeaders
        self.privateHeaders = privateHeaders
        self.resources = resources
        self.resourceBundles = resourceBundles
        self.dependencies = dependencies
        self.linkage = linkage
    }

    private enum CodingKeys: String, CodingKey {
        case sourceFiles
        case publicHeaders
        case privateHeaders
        case resources
        case resourceBundles
        case dependencies
        case linkage
    }

    /// Decodes the original v0.5 development shape by treating an absent linkage group as
    /// empty. Encoding always emits the explicit current shape.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceFiles = try container.decode([String].self, forKey: .sourceFiles)
        publicHeaders = try container.decode([String].self, forKey: .publicHeaders)
        privateHeaders = try container.decode([String].self, forKey: .privateHeaders)
        resources = try container.decode([String].self, forKey: .resources)
        resourceBundles = try container.decode(
            [PodspecResourceBundle].self,
            forKey: .resourceBundles
        )
        dependencies = try container.decode(
            [PodspecDependencyDeclaration].self,
            forKey: .dependencies
        )
        if container.contains(.linkage) {
            linkage = try container.decode(
                PodspecLinkageDeclarations.self,
                forKey: .linkage
            )
        } else {
            linkage = .empty
        }
    }
}

/// One raw platform-specific declaration block such as `ios` or `osx`.
public struct PodspecPlatformScope: Sendable, Equatable, Codable {
    public let platform: PodspecPlatform
    public let path: String
    public let declarations: PodspecScopedDeclarations

    public init(
        platform: PodspecPlatform,
        path: String,
        declarations: PodspecScopedDeclarations
    ) {
        self.platform = platform
        self.path = path
        self.declarations = declarations
    }
}

/// One dependency declaration and its literal, unresolved CocoaPods requirements.
public struct PodspecDependencyDeclaration: Sendable, Equatable, Codable {
    public let name: String
    public let path: String
    public let requirements: [PodspecDependencyRequirement]

    public init(
        name: String,
        path: String,
        requirements: [PodspecDependencyRequirement]
    ) {
        self.name = name
        self.path = path
        self.requirements = requirements
    }
}

/// One exact requirement string from a dependency's JSON array.
///
/// PkgLift records this literal but never parses, solves, normalizes, or projects it to SwiftPM.
public struct PodspecDependencyRequirement: Sendable, Equatable, Codable {
    public let literal: String
    public let path: String

    public init(literal: String, path: String) {
        self.literal = literal
        self.path = path
    }
}

/// A node's explicit or implicit CocoaPods default-subspec policy.
public struct PodspecDefaultSubspecSelection: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        /// No declaration was provided, or an explicit empty list was provided. CocoaPods
        /// selects every immediate library subspec, subject to its effective platform rules.
        case all

        /// The canonical serialized `"none"` form selects no implicit subspec dependencies.
        case none

        /// One or more explicitly named subspecs were selected.
        case named
    }

    public let kind: Kind

    /// The RFC 6901 path to the singular or plural declaration key, if explicit.
    public let declarationPath: String?

    /// The exact value path for `none` or explicit-empty `all`; named values use references.
    public let valuePath: String?

    public let references: [PodspecDefaultSubspecReference]

    public init(
        kind: Kind,
        declarationPath: String?,
        valuePath: String?,
        references: [PodspecDefaultSubspecReference]
    ) {
        self.kind = kind
        self.declarationPath = declarationPath
        self.valuePath = valuePath
        self.references = references
    }

    public static let implicitAll = PodspecDefaultSubspecSelection(
        kind: .all,
        declarationPath: nil,
        valuePath: nil,
        references: []
    )
}

/// One validated default-subspec reference and its declared hierarchy target.
public struct PodspecDefaultSubspecReference: Sendable, Equatable, Codable {
    public let name: String
    public let resolvedName: String
    public let path: String

    public init(name: String, resolvedName: String, path: String) {
        self.name = name
        self.resolvedName = resolvedName
        self.path = path
    }
}

/// A SwiftPM-relevant Apple platform declared by a Podspec.
public enum PodspecPlatform: String, Sendable, Equatable, Codable, CaseIterable {
    case iOS = "ios"
    case macOS = "macos"
    case tvOS = "tvos"
    case watchOS = "watchos"
    case visionOS = "visionos"
}

/// A platform declaration and its optional minimum deployment version.
public struct PodspecPlatformRequirement: Sendable, Equatable, Codable {
    public let platform: PodspecPlatform
    public let minimumVersion: String?

    public init(platform: PodspecPlatform, minimumVersion: String?) {
        self.platform = platform
        self.minimumVersion = minimumVersion
    }
}

/// One named CocoaPods resource bundle and its unexpanded resource declarations.
public struct PodspecResourceBundle: Sendable, Equatable, Codable {
    public let name: String
    public let resources: [String]

    public init(name: String, resources: [String]) {
        self.name = name
        self.resources = resources
    }
}

/// A field or relationship that the inspector deliberately did not interpret completely.
public struct PodspecUnsupportedField: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        /// The field is not part of the recognized Podspec JSON contract at this scope.
        case unknownField

        /// The field or relationship has CocoaPods semantics deferred from this slice.
        case deferredCocoaPodsSemantic
    }

    /// RFC 6901 JSON Pointer identifying the unsupported evidence.
    public let path: String
    public let kind: Kind

    public init(path: String, kind: Kind) {
        self.path = path
        self.kind = kind
    }
}

/// The modeled declarations plus every unsupported semantic field or relationship observed.
public struct PodspecInspection: Sendable, Equatable, Codable {
    public let podspec: PodspecSemanticModel
    public let unsupportedFields: [PodspecUnsupportedField]

    public init(
        podspec: PodspecSemanticModel,
        unsupportedFields: [PodspecUnsupportedField]
    ) {
        self.podspec = podspec
        self.unsupportedFields = unsupportedFields
    }
}

/// Resource limits applied before Podspec JSON can reach the semantic model.
public struct PodspecInspectionLimits: Sendable, Equatable, Codable {
    public let maximumJSONBytes: Int
    public let maximumNestingDepth: Int
    public let maximumContainerElements: Int
    public let maximumTotalValues: Int
    public let maximumStringUTF8Bytes: Int

    public init(
        maximumJSONBytes: Int = 1_048_576,
        maximumNestingDepth: Int = 64,
        maximumContainerElements: Int = 4_096,
        maximumTotalValues: Int = 16_384,
        maximumStringUTF8Bytes: Int = 65_536
    ) {
        self.maximumJSONBytes = maximumJSONBytes
        self.maximumNestingDepth = maximumNestingDepth
        self.maximumContainerElements = maximumContainerElements
        self.maximumTotalValues = maximumTotalValues
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
    }

    public static let `default` = PodspecInspectionLimits()

    /// Absolute recursion ceiling enforced even when a caller supplies custom limits.
    public static let maximumSupportedNestingDepth = 128
}

/// Stable, typed failures produced at the Podspec JSON trust boundary.
public enum PodspecInspectionError: Swift.Error, LocalizedError, Sendable, Equatable {
    case unsupportedSemanticProfile(identifier: String)
    case invalidLimit(name: String, value: Int)
    case inputExceedsLimit(actual: Int, maximum: Int)
    case malformedJSON
    case duplicateObjectKey(path: String)
    case duplicateSubspecIdentity(name: String, path: String, firstPath: String)
    case conflictingDefaultSubspecDeclarations(firstPath: String, secondPath: String)
    case invalidDefaultSubspecReference(name: String, path: String)
    case rootMustBeObject(path: String)
    case missingRequiredField(path: String)
    case invalidValue(path: String, expected: String)
    case limitExceeded(path: String, actual: Int, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSemanticProfile(let identifier):
            return "Unsupported CocoaPods semantic profile: \(identifier)."
        case .invalidLimit(let name, let value):
            return "Invalid Podspec inspection limit \(name): \(value)."
        case .inputExceedsLimit(let actual, let maximum):
            return "Podspec JSON is \(actual) bytes; the maximum is \(maximum)."
        case .malformedJSON:
            return "Podspec input is not valid JSON."
        case .duplicateObjectKey(let path):
            return "Podspec JSON contains a duplicate object key at \(display(path))."
        case .duplicateSubspecIdentity(let name, let path, let firstPath):
            return "Podspec subspec \(name) at \(display(path)) duplicates \(display(firstPath))."
        case .conflictingDefaultSubspecDeclarations(let firstPath, let secondPath):
            return "Podspec defaults conflict at \(display(firstPath)) and \(display(secondPath))."
        case .invalidDefaultSubspecReference(let name, let path):
            return "Podspec default subspec \(name) at \(display(path)) does not identify one declared subspec."
        case .rootMustBeObject(let path):
            return "Podspec JSON value at \(display(path)) must be an object."
        case .missingRequiredField(let path):
            return "Podspec JSON is missing required field \(display(path))."
        case .invalidValue(let path, let expected):
            return "Podspec JSON value at \(display(path)) must be \(expected)."
        case .limitExceeded(let path, let actual, let maximum):
            return "Podspec JSON value at \(display(path)) exceeds a limit: \(actual) > \(maximum)."
        }
    }

    private func display(_ path: String) -> String {
        path.isEmpty ? "<root>" : path
    }
}
