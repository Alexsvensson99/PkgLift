// PkgLiftCocoaPods/PodspecSemanticDecoder.swift
// Version-bound decoding of recursive CocoaPods Core Podspec declarations.

import CoreFoundation
import Foundation

struct DecodedPodspecSemantics {
    let version: String
    let root: PodspecNode
    let unsupportedFields: [PodspecUnsupportedField]
}

struct PodspecSemanticDecoder {
    private var unsupportedFields: [PodspecUnsupportedField] = []

    private struct DeclarationContext {
        let ownerIsRoot: Bool
        let isPlatformScope: Bool

        var allowsRootGlobalDeclarations: Bool {
            ownerIsRoot && !isPlatformScope
        }

        var allowsModuleMap: Bool {
            ownerIsRoot
        }
    }

    mutating func decode(_ root: [String: Any]) throws -> DecodedPodspecSemantics {
        let version = try requiredString(named: "version", in: root, at: "")
        let node = try parseNode(root, path: "", parentName: nil, isRoot: true)
        return DecodedPodspecSemantics(
            version: version,
            root: node,
            unsupportedFields: unsupportedFields.sorted(by: Self.unsupportedFieldOrder)
        )
    }

    private mutating func parseNode(
        _ object: [String: Any],
        path: String,
        parentName: String?,
        isRoot: Bool
    ) throws -> PodspecNode {
        let baseName = try requiredIdentityName(in: object, at: path)
        let fullName = parentName.map { "\($0)/\(baseName)" } ?? baseName

        if !isRoot, object["version"] != nil {
            throw PodspecInspectionError.invalidValue(
                path: Self.path("version", beneath: path),
                expected: "absent because version is a root-only declaration"
            )
        }
        if !isRoot,
           object["default_subspec"] != nil || object["default_subspecs"] != nil {
            let key = object["default_subspecs"] != nil
                ? "default_subspecs"
                : "default_subspec"
            throw PodspecInspectionError.invalidValue(
                path: Self.path(key, beneath: path),
                expected: "absent because defaults are root-only declarations"
            )
        }

        let declarations = try parseDeclarations(
            in: object,
            at: path,
            context: DeclarationContext(ownerIsRoot: isRoot, isPlatformScope: false)
        )
        let platforms = try parsePlatforms(in: object, at: path)
        let platformScopes = try parsePlatformScopes(
            in: object,
            at: path,
            ownerIsRoot: isRoot
        )
        let subspecs = try parseSubspecs(
            in: object,
            at: path,
            parentName: fullName
        )
        let defaults = isRoot
            ? try parseDefaultSubspecs(in: object, root: fullName, subspecs: subspecs)
            : .implicitAll

        classifyUnsupportedNodeFields(in: object, at: path, isRoot: isRoot)

        return PodspecNode(
            name: fullName,
            baseName: baseName,
            path: path,
            platforms: platforms,
            declarations: declarations,
            platformScopes: platformScopes,
            defaultSubspecs: defaults,
            subspecs: subspecs
        )
    }

    private func requiredIdentityName(
        in object: [String: Any],
        at path: String
    ) throws -> String {
        let name = try requiredString(named: "name", in: object, at: path)
        guard !name.hasPrefix("."),
              !name.contains("/"),
              !name.contains(where: \Character.isWhitespace) else {
            throw PodspecInspectionError.invalidValue(
                path: Self.path("name", beneath: path),
                expected: "a CocoaPods name without slash or whitespace and not beginning with a period"
            )
        }
        return name
    }

    private func requiredString(
        named name: String,
        in object: [String: Any],
        at path: String
    ) throws -> String {
        let fieldPath = Self.path(name, beneath: path)
        guard let value = object[name] else {
            throw PodspecInspectionError.missingRequiredField(path: fieldPath)
        }
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PodspecInspectionError.invalidValue(
                path: fieldPath,
                expected: "a non-empty string"
            )
        }
        return string
    }

    private mutating func parseDeclarations(
        in object: [String: Any],
        at path: String,
        context: DeclarationContext
    ) throws -> PodspecScopedDeclarations {
        PodspecScopedDeclarations(
            sourceFiles: try parseStringList(
                object["source_files"],
                path: Self.path("source_files", beneath: path)
            ),
            publicHeaders: try parseStringList(
                object["public_header_files"],
                path: Self.path("public_header_files", beneath: path)
            ),
            privateHeaders: try parseStringList(
                object["private_header_files"],
                path: Self.path("private_header_files", beneath: path)
            ),
            resources: try parseStringList(
                object["resources"],
                path: Self.path("resources", beneath: path)
            ),
            resourceBundles: try parseResourceBundles(in: object, at: path),
            dependencies: try parseDependencies(in: object, at: path),
            linkage: try parseLinkageDeclarations(
                in: object,
                at: path,
                context: context
            )
        )
    }

    private func parseLinkageDeclarations(
        in object: [String: Any],
        at path: String,
        context: DeclarationContext
    ) throws -> PodspecLinkageDeclarations {
        try validateLinkageDeclarationScopes(in: object, at: path, context: context)

        return PodspecLinkageDeclarations(
            frameworks: try parseLiteralList(
                object["frameworks"],
                path: Self.path("frameworks", beneath: path)
            ),
            weakFrameworks: try parseLiteralList(
                object["weak_frameworks"],
                path: Self.path("weak_frameworks", beneath: path)
            ),
            libraries: try parseLiteralList(
                object["libraries"],
                path: Self.path("libraries", beneath: path)
            ),
            vendoredFrameworks: try parseLiteralList(
                object["vendored_frameworks"],
                path: Self.path("vendored_frameworks", beneath: path)
            ),
            vendoredLibraries: try parseLiteralList(
                object["vendored_libraries"],
                path: Self.path("vendored_libraries", beneath: path)
            ),
            moduleName: try parseOptionalLiteral(
                object["module_name"],
                path: Self.path("module_name", beneath: path)
            ),
            moduleMap: try parseModuleMap(
                object["module_map"],
                path: Self.path("module_map", beneath: path)
            ),
            headerDirectory: try parseOptionalLiteral(
                object["header_dir"],
                path: Self.path("header_dir", beneath: path)
            ),
            headerMappingsDirectory: try parseOptionalLiteral(
                object["header_mappings_dir"],
                path: Self.path("header_mappings_dir", beneath: path)
            ),
            projectHeaders: try parseLiteralList(
                object["project_header_files"],
                path: Self.path("project_header_files", beneath: path)
            ),
            staticFramework: try parseOptionalBoolean(
                object["static_framework"],
                path: Self.path("static_framework", beneath: path)
            )
        )
    }

    private func validateLinkageDeclarationScopes(
        in object: [String: Any],
        at path: String,
        context: DeclarationContext
    ) throws {
        if object["module_name"] != nil, !context.allowsRootGlobalDeclarations {
            throw PodspecInspectionError.invalidValue(
                path: Self.path("module_name", beneath: path),
                expected: "absent because module_name is a root-only, non-platform declaration"
            )
        }
        if object["static_framework"] != nil, !context.allowsRootGlobalDeclarations {
            throw PodspecInspectionError.invalidValue(
                path: Self.path("static_framework", beneath: path),
                expected: "absent because static_framework is a root-only, non-platform declaration"
            )
        }
        if object["module_map"] != nil, !context.allowsModuleMap {
            throw PodspecInspectionError.invalidValue(
                path: Self.path("module_map", beneath: path),
                expected: "absent because module_map is a root-only declaration"
            )
        }
    }

    private func parseLiteralList(
        _ value: Any?,
        path: String
    ) throws -> [PodspecLiteralDeclaration] {
        guard let value else { return [] }
        if let string = value as? String {
            return [PodspecLiteralDeclaration(
                literal: try nonEmptyLiteral(string, path: path),
                path: path
            )]
        }
        guard let array = value as? [Any] else {
            throw PodspecInspectionError.invalidValue(
                path: path,
                expected: "a non-empty string or an array of non-empty strings"
            )
        }

        return try array.enumerated().map { index, element in
            let elementPath = Self.path(String(index), beneath: path)
            guard let string = element as? String else {
                throw PodspecInspectionError.invalidValue(
                    path: elementPath,
                    expected: "a non-empty string"
                )
            }
            return PodspecLiteralDeclaration(
                literal: try nonEmptyLiteral(string, path: elementPath),
                path: elementPath
            )
        }
    }

    private func parseOptionalLiteral(
        _ value: Any?,
        path: String
    ) throws -> PodspecLiteralDeclaration? {
        guard let value else { return nil }
        guard let string = value as? String else {
            throw PodspecInspectionError.invalidValue(
                path: path,
                expected: "a non-empty string"
            )
        }
        return PodspecLiteralDeclaration(
            literal: try nonEmptyLiteral(string, path: path),
            path: path
        )
    }

    private func parseModuleMap(
        _ value: Any?,
        path: String
    ) throws -> PodspecModuleMapDeclaration? {
        guard let value else { return nil }
        if let string = value as? String {
            return PodspecModuleMapDeclaration(
                value: .customPath(try nonEmptyLiteral(string, path: path)),
                path: path
            )
        }
        guard let boolean = strictBoolean(value) else {
            throw PodspecInspectionError.invalidValue(
                path: path,
                expected: "a non-empty path string or a boolean"
            )
        }
        return PodspecModuleMapDeclaration(
            value: boolean ? .generated : .disabled,
            path: path
        )
    }

    private func parseOptionalBoolean(
        _ value: Any?,
        path: String
    ) throws -> PodspecBooleanDeclaration? {
        guard let value else { return nil }
        guard let boolean = strictBoolean(value) else {
            throw PodspecInspectionError.invalidValue(
                path: path,
                expected: "a boolean"
            )
        }
        return PodspecBooleanDeclaration(value: boolean, path: path)
    }

    private func strictBoolean(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    private func parseStringList(_ value: Any?, path: String) throws -> [String] {
        guard let value else { return [] }
        if let string = value as? String {
            return [try nonEmptyLiteral(string, path: path)]
        }
        guard let array = value as? [Any] else {
            throw PodspecInspectionError.invalidValue(
                path: path,
                expected: "a string or an array of strings"
            )
        }

        return try array.enumerated().map { index, element in
            let elementPath = Self.path(String(index), beneath: path)
            guard let string = element as? String else {
                throw PodspecInspectionError.invalidValue(
                    path: elementPath,
                    expected: "a non-empty string"
                )
            }
            return try nonEmptyLiteral(string, path: elementPath)
        }
    }

    private func nonEmptyLiteral(_ value: String, path: String) throws -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PodspecInspectionError.invalidValue(
                path: path,
                expected: "a non-empty string"
            )
        }
        return value
    }

    private mutating func parsePlatforms(
        in object: [String: Any],
        at path: String
    ) throws -> [PodspecPlatformRequirement] {
        guard let rawPlatforms = object["platforms"] else { return [] }
        let platformsPath = Self.path("platforms", beneath: path)
        guard let platforms = rawPlatforms as? [String: Any] else {
            throw PodspecInspectionError.invalidValue(
                path: platformsPath,
                expected: "an object"
            )
        }

        var requirements: [PodspecPlatformRequirement] = []
        for key in platforms.keys.sorted() {
            guard let platform = Self.platform(forPodspecKey: key),
                  let rawMinimum = platforms[key] else {
                unsupportedFields.append(PodspecUnsupportedField(
                    path: Self.path(key, beneath: platformsPath),
                    kind: .unknownField
                ))
                continue
            }
            let minimumPath = Self.path(key, beneath: platformsPath)
            let minimumVersion: String?
            if rawMinimum is NSNull {
                minimumVersion = nil
            } else if let string = rawMinimum as? String,
                      !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                minimumVersion = string
            } else {
                throw PodspecInspectionError.invalidValue(
                    path: minimumPath,
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

    private mutating func parseResourceBundles(
        in object: [String: Any],
        at path: String
    ) throws -> [PodspecResourceBundle] {
        guard let rawBundles = object["resource_bundles"] else { return [] }
        let bundlesPath = Self.path("resource_bundles", beneath: path)
        guard let bundles = rawBundles as? [String: Any] else {
            throw PodspecInspectionError.invalidValue(
                path: bundlesPath,
                expected: "an object"
            )
        }

        return try bundles.keys.sorted().map { name in
            let bundlePath = Self.path(name, beneath: bundlesPath)
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let value = bundles[name] else {
                throw PodspecInspectionError.invalidValue(
                    path: bundlePath,
                    expected: "a non-empty resource bundle name"
                )
            }
            return PodspecResourceBundle(
                name: name,
                resources: try parseStringList(value, path: bundlePath)
            )
        }
    }

    private mutating func parseDependencies(
        in object: [String: Any],
        at path: String
    ) throws -> [PodspecDependencyDeclaration] {
        guard let rawDependencies = object["dependencies"] else { return [] }
        let dependenciesPath = Self.path("dependencies", beneath: path)
        guard let dependencies = rawDependencies as? [String: Any] else {
            throw PodspecInspectionError.invalidValue(
                path: dependenciesPath,
                expected: "an object of dependency requirement arrays"
            )
        }

        return try dependencies.keys.sorted().map { name in
            let dependencyPath = Self.path(name, beneath: dependenciesPath)
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let rawRequirements = dependencies[name] else {
                throw PodspecInspectionError.invalidValue(
                    path: dependencyPath,
                    expected: "a non-empty dependency name"
                )
            }
            guard let requirements = rawRequirements as? [Any] else {
                throw PodspecInspectionError.invalidValue(
                    path: dependencyPath,
                    expected: "an array of non-empty literal requirement strings"
                )
            }

            let declarations = try requirements.enumerated().map { index, rawValue in
                let requirementPath = Self.path(String(index), beneath: dependencyPath)
                guard let literal = rawValue as? String,
                      !literal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw PodspecInspectionError.invalidValue(
                        path: requirementPath,
                        expected: "a non-empty literal requirement string"
                    )
                }
                return PodspecDependencyRequirement(
                    literal: literal,
                    path: requirementPath
                )
            }
            return PodspecDependencyDeclaration(
                name: name,
                path: dependencyPath,
                requirements: declarations
            )
        }
    }

    private mutating func parsePlatformScopes(
        in object: [String: Any],
        at path: String,
        ownerIsRoot: Bool
    ) throws -> [PodspecPlatformScope] {
        var scopes: [PodspecPlatformScope] = []
        for key in Self.platformJSONKeys {
            guard let rawScope = object[key] else { continue }
            let scopePath = Self.path(key, beneath: path)
            guard let scope = rawScope as? [String: Any],
                  let platform = Self.platform(forPodspecKey: key) else {
                throw PodspecInspectionError.invalidValue(
                    path: scopePath,
                    expected: "an object"
                )
            }

            if scope["default_subspec"] != nil || scope["default_subspecs"] != nil {
                let defaultKey = scope["default_subspecs"] != nil
                    ? "default_subspecs"
                    : "default_subspec"
                throw PodspecInspectionError.invalidValue(
                    path: Self.path(defaultKey, beneath: scopePath),
                    expected: "absent because defaults are root-only declarations"
                )
            }

            classifyUnsupportedPlatformFields(in: scope, at: scopePath)
            scopes.append(PodspecPlatformScope(
                platform: platform,
                path: scopePath,
                declarations: try parseDeclarations(
                    in: scope,
                    at: scopePath,
                    context: DeclarationContext(
                        ownerIsRoot: ownerIsRoot,
                        isPlatformScope: true
                    )
                )
            ))
            unsupportedFields.append(PodspecUnsupportedField(
                path: scopePath,
                kind: .deferredCocoaPodsSemantic
            ))
        }
        return scopes
    }

    private mutating func parseSubspecs(
        in object: [String: Any],
        at path: String,
        parentName: String
    ) throws -> [PodspecNode] {
        guard let rawSubspecs = object["subspecs"] else { return [] }
        let subspecsPath = Self.path("subspecs", beneath: path)
        guard let subspecObjects = rawSubspecs as? [Any] else {
            throw PodspecInspectionError.invalidValue(
                path: subspecsPath,
                expected: "an array of subspec objects"
            )
        }

        var nodes: [PodspecNode] = []
        var firstNamePaths: [String: String] = [:]
        for (index, rawNode) in subspecObjects.enumerated() {
            let nodePath = Self.path(String(index), beneath: subspecsPath)
            guard let nodeObject = rawNode as? [String: Any] else {
                throw PodspecInspectionError.invalidValue(
                    path: nodePath,
                    expected: "a subspec object"
                )
            }
            let node = try parseNode(
                nodeObject,
                path: nodePath,
                parentName: parentName,
                isRoot: false
            )
            let namePath = Self.path("name", beneath: nodePath)
            if let firstPath = firstNamePaths[node.baseName] {
                throw PodspecInspectionError.duplicateSubspecIdentity(
                    name: node.name,
                    path: namePath,
                    firstPath: firstPath
                )
            }
            firstNamePaths[node.baseName] = namePath
            nodes.append(node)
            unsupportedFields.append(PodspecUnsupportedField(
                path: nodePath,
                kind: .deferredCocoaPodsSemantic
            ))
        }
        return nodes
    }

    private func parseDefaultSubspecs(
        in rootObject: [String: Any],
        root: String,
        subspecs: [PodspecNode]
    ) throws -> PodspecDefaultSubspecSelection {
        let singularKey = "default_subspec"
        let pluralKey = "default_subspecs"
        if rootObject[singularKey] != nil, rootObject[pluralKey] != nil {
            throw PodspecInspectionError.conflictingDefaultSubspecDeclarations(
                firstPath: "/default_subspec",
                secondPath: "/default_subspecs"
            )
        }

        let key: String
        if rootObject[pluralKey] != nil {
            key = pluralKey
        } else if rootObject[singularKey] != nil {
            key = singularKey
        } else {
            return .implicitAll
        }
        let declarationPath = Self.path(key, beneath: "")
        guard let rawValue = rootObject[key] else { return .implicitAll }

        let literals: [(value: String, path: String)]
        if let value = rawValue as? String {
            literals = [(value, declarationPath)]
        } else if key == pluralKey, let values = rawValue as? [Any] {
            if values.isEmpty {
                return PodspecDefaultSubspecSelection(
                    kind: .all,
                    declarationPath: declarationPath,
                    valuePath: declarationPath,
                    references: []
                )
            }
            literals = try values.enumerated().map { index, value in
                let valuePath = Self.path(String(index), beneath: declarationPath)
                guard let string = value as? String,
                      !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw PodspecInspectionError.invalidValue(
                        path: valuePath,
                        expected: "a non-empty default subspec name"
                    )
                }
                return (string, valuePath)
            }
        } else {
            throw PodspecInspectionError.invalidValue(
                path: declarationPath,
                expected: key == pluralKey
                    ? "a non-empty string or an array of non-empty strings"
                    : "a non-empty string"
            )
        }

        if literals.count == 1, literals[0].value == "none" {
            return PodspecDefaultSubspecSelection(
                kind: .none,
                declarationPath: declarationPath,
                valuePath: literals[0].path,
                references: []
            )
        }
        if let none = literals.first(where: { $0.value == "none" }) {
            throw PodspecInspectionError.invalidValue(
                path: none.path,
                expected: "the sole default value when using the reserved none form"
            )
        }

        var seen: Set<String> = []
        let references = try literals.map { literal in
            guard seen.insert(literal.value).inserted else {
                throw PodspecInspectionError.invalidValue(
                    path: literal.path,
                    expected: "a unique default subspec reference"
                )
            }
            guard let resolvedName = Self.resolveDefaultReference(
                literal.value,
                root: root,
                subspecs: subspecs
            ) else {
                throw PodspecInspectionError.invalidDefaultSubspecReference(
                    name: literal.value,
                    path: literal.path
                )
            }
            return PodspecDefaultSubspecReference(
                name: literal.value,
                resolvedName: resolvedName,
                path: literal.path
            )
        }
        return PodspecDefaultSubspecSelection(
            kind: .named,
            declarationPath: declarationPath,
            valuePath: nil,
            references: references
        )
    }

    private mutating func classifyUnsupportedNodeFields(
        in object: [String: Any],
        at path: String,
        isRoot: Bool
    ) {
        var modeled = Self.modeledNodeFields
        if isRoot {
            modeled.formUnion(Self.modeledRootOnlyFields)
        }
        classifyUnsupportedFields(
            in: object,
            at: path,
            modeled: modeled,
            allowsDescriptiveMetadata: isRoot
        )
    }

    private mutating func classifyUnsupportedPlatformFields(
        in object: [String: Any],
        at path: String
    ) {
        classifyUnsupportedFields(
            in: object,
            at: path,
            modeled: Self.modeledDeclarationFields,
            allowsDescriptiveMetadata: false
        )
    }

    private mutating func classifyUnsupportedFields(
        in object: [String: Any],
        at path: String,
        modeled: Set<String>,
        allowsDescriptiveMetadata: Bool
    ) {
        for key in object.keys.sorted() {
            if modeled.contains(key) {
                continue
            }
            if allowsDescriptiveMetadata, Self.descriptiveMetadataFields.contains(key) {
                continue
            }
            let kind: PodspecUnsupportedField.Kind = Self.deferredSemanticFields.contains(key)
                || Self.descriptiveMetadataFields.contains(key)
                ? .deferredCocoaPodsSemantic
                : .unknownField
            unsupportedFields.append(PodspecUnsupportedField(
                path: Self.path(key, beneath: path),
                kind: kind
            ))
        }
    }

    private static func resolveDefaultReference(
        _ reference: String,
        root: String,
        subspecs: [PodspecNode]
    ) -> String? {
        let components = reference.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }

        var candidates = subspecs
        var resolved: PodspecNode?
        for component in components {
            guard let match = candidates.first(where: { $0.baseName == String(component) }) else {
                return nil
            }
            resolved = match
            candidates = match.subspecs
        }
        guard let resolved, resolved.name.hasPrefix("\(root)/") else { return nil }
        return resolved.name
    }

    private static func unsupportedFieldOrder(
        _ lhs: PodspecUnsupportedField,
        _ rhs: PodspecUnsupportedField
    ) -> Bool {
        if lhs.path == rhs.path {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.path < rhs.path
    }

    private static func path(_ component: String, beneath path: String) -> String {
        PodspecJSONPointer.appending(component, to: path)
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

    private static let platformJSONKeys = [
        "ios",
        "osx",
        "tvos",
        "watchos",
        "visionos",
    ]

    private static let modeledDeclarationFields: Set<String> = [
        "source_files",
        "public_header_files",
        "private_header_files",
        "resources",
        "resource_bundles",
        "dependencies",
        "frameworks",
        "weak_frameworks",
        "libraries",
        "vendored_frameworks",
        "vendored_libraries",
        "module_map",
        "header_dir",
        "header_mappings_dir",
        "project_header_files",
    ]

    private static let modeledNodeFields: Set<String> = modeledDeclarationFields.union([
        "name",
        "platforms",
        "subspecs",
        "ios",
        "osx",
        "tvos",
        "watchos",
        "visionos",
    ])

    private static let modeledRootOnlyFields: Set<String> = [
        "version",
        "default_subspec",
        "default_subspecs",
        "module_name",
        "static_framework",
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
        "app_host_name",
        "appspecs",
        "compiler_flags",
        "cocoapods_version",
        "configuration_pod_whitelist",
        "exclude_files",
        "info_plist",
        "on_demand_resources",
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
        "swift_version",
        "swift_versions",
        "test_type",
        "testspecs",
        "user_target_xcconfig",
        "xcconfig",
    ]
}
