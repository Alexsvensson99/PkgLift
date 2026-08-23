// PkgLiftCocoaPods/PodspecSemanticModel.swift
// Typed, analysis-only representation of bounded Podspec JSON semantics.

import Foundation

/// The bounded semantic subset extracted from an already available Podspec JSON document.
///
/// This model describes declarations only. It is not evidence that a pod can be represented
/// by SwiftPM and it does not affect migration classification or AUTO eligibility.
public struct PodspecSemanticModel: Sendable, Equatable, Codable {
    public let name: String
    public let version: String
    public let platforms: [PodspecPlatformRequirement]
    public let sourceFiles: [String]
    public let publicHeaders: [String]
    public let privateHeaders: [String]
    public let resources: [String]
    public let resourceBundles: [PodspecResourceBundle]

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
        self.name = name
        self.version = version
        self.platforms = platforms
        self.sourceFiles = sourceFiles
        self.publicHeaders = publicHeaders
        self.privateHeaders = privateHeaders
        self.resources = resources
        self.resourceBundles = resourceBundles
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

/// A field that the inspector deliberately did not include in the semantic model.
public struct PodspecUnsupportedField: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        /// The field is not part of the recognized Podspec JSON contract.
        case unknownField

        /// The field has CocoaPods semantics that are deferred from this implementation slice.
        case deferredCocoaPodsSemantic
    }

    /// RFC 6901 JSON Pointer identifying the unsupported field.
    public let path: String
    public let kind: Kind

    public init(path: String, kind: Kind) {
        self.path = path
        self.kind = kind
    }
}

/// The modeled declarations plus every unsupported semantic field observed in the input.
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
    case invalidLimit(name: String, value: Int)
    case inputExceedsLimit(actual: Int, maximum: Int)
    case malformedJSON
    case duplicateObjectKey(path: String)
    case rootMustBeObject(path: String)
    case missingRequiredField(path: String)
    case invalidValue(path: String, expected: String)
    case limitExceeded(path: String, actual: Int, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let name, let value):
            return "Invalid Podspec inspection limit \(name): \(value)."
        case .inputExceedsLimit(let actual, let maximum):
            return "Podspec JSON is \(actual) bytes; the maximum is \(maximum)."
        case .malformedJSON:
            return "Podspec input is not valid JSON."
        case .duplicateObjectKey(let path):
            return "Podspec JSON contains a duplicate object key at \(display(path))."
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
