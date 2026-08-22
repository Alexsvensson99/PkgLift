// PkgLiftCocoaPods/PodspecJSONInspector.swift
// Offline, in-memory inspection of a bounded Podspec JSON semantic subset.

import Foundation

/// Inspects already available `.podspec.json` data without executing Ruby,
/// reading files, resolving globs, starting processes, or contacting a network.
public struct PodspecJSONInspector: Sendable {
    private let limits: PodspecInspectionLimits

    public init(limits: PodspecInspectionLimits = .default) {
        self.limits = limits
    }

    public func inspect(json data: Data) throws -> PodspecInspection {
        try validateLimits()
        guard data.count <= limits.maximumJSONBytes else {
            throw PodspecInspectionError.inputExceedsLimit(
                actual: data.count,
                maximum: limits.maximumJSONBytes
            )
        }

        var boundaryScanner = PodspecJSONBoundaryScanner(data: data, limits: limits)
        try boundaryScanner.validate()

        let rawRoot: Any
        do {
            rawRoot = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw PodspecInspectionError.malformedJSON
        }

        guard let root = rawRoot as? [String: Any] else {
            throw PodspecInspectionError.rootMustBeObject(path: "")
        }

        let model = PodspecSemanticModel(
            name: try requiredString(named: "name", in: root),
            version: try requiredString(named: "version", in: root),
            platforms: try parsePlatforms(in: root),
            sourceFiles: try parseStringList(root["source_files"], path: "/source_files"),
            publicHeaders: try parseStringList(
                root["public_header_files"],
                path: "/public_header_files"
            ),
            privateHeaders: try parseStringList(
                root["private_header_files"],
                path: "/private_header_files"
            ),
            resources: try parseStringList(root["resources"], path: "/resources"),
            resourceBundles: try parseResourceBundles(in: root)
        )

        return PodspecInspection(
            podspec: model,
            unsupportedFields: unsupportedFields(in: root)
        )
    }

    private func validateLimits() throws {
        let positiveLimits = [
            ("maximumJSONBytes", limits.maximumJSONBytes),
            ("maximumContainerElements", limits.maximumContainerElements),
            ("maximumTotalValues", limits.maximumTotalValues),
            ("maximumStringUTF8Bytes", limits.maximumStringUTF8Bytes),
        ]
        if let invalid = positiveLimits.first(where: { $0.1 < 1 }) {
            throw PodspecInspectionError.invalidLimit(
                name: invalid.0,
                value: invalid.1
            )
        }
        guard limits.maximumNestingDepth >= 0,
              limits.maximumNestingDepth <= PodspecInspectionLimits.maximumSupportedNestingDepth else {
            throw PodspecInspectionError.invalidLimit(
                name: "maximumNestingDepth",
                value: limits.maximumNestingDepth
            )
        }
    }

    private func requiredString(
        named name: String,
        in root: [String: Any]
    ) throws -> String {
        let path = Self.appending(name, to: "")
        guard let value = root[name] else {
            throw PodspecInspectionError.missingRequiredField(path: path)
        }
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PodspecInspectionError.invalidValue(
                path: path,
                expected: "a non-empty string"
            )
        }
        return string
    }

    private func parseStringList(_ value: Any?, path: String) throws -> [String] {
        guard let value else { return [] }
        if let string = value as? String {
            return [try nonEmptyPathDeclaration(string, path: path)]
        }
        guard let array = value as? [Any] else {
            throw PodspecInspectionError.invalidValue(
                path: path,
                expected: "a string or an array of strings"
            )
        }

        return try array.enumerated().map { index, element in
            let elementPath = Self.appending(String(index), to: path)
            guard let string = element as? String else {
                throw PodspecInspectionError.invalidValue(
                    path: elementPath,
                    expected: "a non-empty string"
                )
            }
            return try nonEmptyPathDeclaration(string, path: elementPath)
        }
    }

    private func nonEmptyPathDeclaration(_ value: String, path: String) throws -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PodspecInspectionError.invalidValue(
                path: path,
                expected: "a non-empty string"
            )
        }
        return value
    }

    private func parsePlatforms(
        in root: [String: Any]
    ) throws -> [PodspecPlatformRequirement] {
        guard let rawPlatforms = root["platforms"] else { return [] }
        guard let platforms = rawPlatforms as? [String: Any] else {
            throw PodspecInspectionError.invalidValue(
                path: "/platforms",
                expected: "an object"
            )
        }

        var requirements: [PodspecPlatformRequirement] = []
        for key in platforms.keys.sorted() {
            guard let platform = Self.platform(forPodspecKey: key),
                  let rawMinimum = platforms[key] else {
                continue
            }
            let path = Self.appending(key, to: "/platforms")
            let minimumVersion: String?
            if rawMinimum is NSNull {
                minimumVersion = nil
            } else if let string = rawMinimum as? String,
                      !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                minimumVersion = string
            } else {
                throw PodspecInspectionError.invalidValue(
                    path: path,
                    expected: "a non-empty version string or null"
                )
            }
            requirements.append(PodspecPlatformRequirement(
                platform: platform,
                minimumVersion: minimumVersion
            ))
        }

        return requirements.sorted {
            Self.platformRank($0.platform) < Self.platformRank($1.platform)
        }
    }

    private func parseResourceBundles(
        in root: [String: Any]
    ) throws -> [PodspecResourceBundle] {
        guard let rawBundles = root["resource_bundles"] else { return [] }
        guard let bundles = rawBundles as? [String: Any] else {
            throw PodspecInspectionError.invalidValue(
                path: "/resource_bundles",
                expected: "an object"
            )
        }

        return try bundles.keys.sorted().map { name in
            let path = Self.appending(name, to: "/resource_bundles")
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let value = bundles[name] else {
                throw PodspecInspectionError.invalidValue(
                    path: path,
                    expected: "a non-empty resource bundle name"
                )
            }
            return PodspecResourceBundle(
                name: name,
                resources: try parseStringList(value, path: path)
            )
        }
    }

    private func unsupportedFields(
        in root: [String: Any]
    ) -> [PodspecUnsupportedField] {
        var fields: [PodspecUnsupportedField] = []
        for key in root.keys.sorted() {
            if Self.supportedRootFields.contains(key)
                || Self.descriptiveMetadataFields.contains(key) {
                continue
            }
            let kind: PodspecUnsupportedField.Kind = Self.deferredSemanticFields.contains(key)
                ? .deferredCocoaPodsSemantic
                : .unknownField
            fields.append(PodspecUnsupportedField(
                path: Self.appending(key, to: ""),
                kind: kind
            ))
        }

        if let platforms = root["platforms"] as? [String: Any] {
            for key in platforms.keys.sorted()
            where Self.platform(forPodspecKey: key) == nil {
                fields.append(PodspecUnsupportedField(
                    path: Self.appending(key, to: "/platforms"),
                    kind: .unknownField
                ))
            }
        }

        return fields.sorted {
            if $0.path == $1.path {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.path < $1.path
        }
    }

    private static func appending(_ component: String, to path: String) -> String {
        let escaped = component
            .replacingOccurrences(of: "~", with: "~0")
            .replacingOccurrences(of: "/", with: "~1")
        return "\(path)/\(escaped)"
    }

    private static func platform(forPodspecKey key: String) -> PodspecPlatform? {
        switch key {
        case "ios": .iOS
        case "osx": .macOS
        case "tvos": .tvOS
        case "watchos": .watchOS
        case "visionos": .visionOS
        default: nil
        }
    }

    private static func platformRank(_ platform: PodspecPlatform) -> Int {
        switch platform {
        case .iOS: 0
        case .macOS: 1
        case .tvOS: 2
        case .watchOS: 3
        case .visionOS: 4
        }
    }

    private static let supportedRootFields: Set<String> = [
        "name",
        "version",
        "platforms",
        "source_files",
        "public_header_files",
        "private_header_files",
        "resources",
        "resource_bundles",
    ]

    private static let descriptiveMetadataFields: Set<String> = [
        "authors",
        "changelog",
        "deprecated",
        "deprecated_in_favor_of",
        "description",
        "documentation_url",
        "homepage",
        "license",
        "readme",
        "screenshots",
        "social_media_url",
        "summary",
    ]

    private static let deferredSemanticFields: Set<String> = [
        "appspecs",
        "compiler_flags",
        "cocoapods_version",
        "default_subspec",
        "default_subspecs",
        "dependencies",
        "exclude_files",
        "frameworks",
        "header_dir",
        "header_mappings_dir",
        "info_plist",
        "ios",
        "libraries",
        "module_map",
        "module_name",
        "on_demand_resources",
        "osx",
        "pod_target_xcconfig",
        "prefix_header_contents",
        "prefix_header_file",
        "prepare_command",
        "preserve_paths",
        "requires_app_host",
        "requires_arc",
        "scheme",
        "script_phase",
        "script_phases",
        "source",
        "static_framework",
        "static_library",
        "subspecs",
        "swift_version",
        "swift_versions",
        "testspecs",
        "tvos",
        "user_target_xcconfig",
        "vendored_frameworks",
        "vendored_libraries",
        "visionos",
        "watchos",
        "weak_frameworks",
        "xcconfig",
    ]
}
