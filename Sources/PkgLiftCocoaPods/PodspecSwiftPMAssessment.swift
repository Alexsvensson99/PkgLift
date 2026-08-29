// PkgLiftCocoaPods/PodspecSwiftPMAssessment.swift
// Pure, versioned, analysis-only SwiftPM capability assessment.

import Foundation

/// The SwiftPM declaration capabilities used for one assessment.
///
/// Capability profiles are explicit because SwiftPM's manifest surface changes with the
/// tools version. Callers cannot request an unknown profile and silently inherit current
/// behavior.
public struct SwiftPMCapabilityProfile: Sendable, Hashable, Codable, RawRepresentable {
    public let rawValue: String

    public var identifier: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(identifier: String) {
        self.init(rawValue: identifier)
    }

    /// The deliberately conservative declaration surface of Swift tools version 6.0.
    ///
    /// This profile does not authorize unsafe flags, infer filesystem layouts, resolve
    /// packages, or claim that an emitted package would build.
    public static let swiftToolsVersion6_0 = SwiftPMCapabilityProfile(
        rawValue: "swift-tools-version/6.0"
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

/// One privacy-bounded reason behind a Podspec-to-SwiftPM assessment.
///
/// `evidencePath` is a canonical, privacy-bounded locator that uses RFC 6901 escaping rules.
/// It is not guaranteed to dereference the original Podspec JSON: dynamically keyed maps use
/// stable semantic-model indices, and unknown or deferred fields use their inspection index.
/// Attacker-controlled keys and raw declaration values are deliberately excluded so flags,
/// credentials, and local paths stay caller-owned.
public struct PodspecSwiftPMAssessmentReason: Sendable, Hashable, Codable {
    public enum Code: String, Sendable, Hashable, Codable, CaseIterable {
        case incompleteModeledSemantic
        case unknownCocoaPodsSemantic
        case deferredCocoaPodsSemantic
        case platformRequiresGeneratedMetadata
        case platformScopeSemanticsIndeterminate
        case subspecSemanticsIndeterminate
        case defaultSubspecRequiresGeneratedMetadata
        case sourceSelectionRequiresGeneratedMetadata
        case headerSelectionRequiresGeneratedMetadata
        case resourceSelectionRequiresGeneratedMetadata
        case resourceBundleRequiresGeneratedMetadata
        case dependencyRequiresGeneratedMetadata
        case linkerSettingRequiresGeneratedMetadata
        case weakFrameworkLinkageUnsupported
        case vendoredArtifactRequiresInspection
        case moduleNameRequiresGeneratedMetadata
        case generatedModuleMapRequiresGeneratedMetadata
        case customModuleMapRequiresInspection
        case disabledModuleMapUnsupported
        case headerLayoutRequiresGeneratedMetadata
        case linkageModeRequiresGeneratedMetadata
        case compilerFlagsUnsupported
        case buildSettingsUnsupported
        case configurationSpecificDependencyUnsupported
        case swiftVersionRequiresInspection
        case arcControlUnsupported
        case fileExclusionRequiresGeneratedMetadata
        case preservePathUnsupported
    }

    public let code: Code
    public let evidencePath: String

    public init(code: Code, evidencePath: String) {
        self.code = code
        self.evidencePath = evidencePath
    }
}

/// A deterministic declaration-level comparison between one Podspec inspection and SwiftPM.
///
/// Even `declarationCompatible` is analysis evidence only. It does not prove file selection,
/// package validity, source, resource, linkage, language, build, or runtime equivalence, and
/// no outcome can authorize migration or `AUTO` eligibility.
public struct PodspecSwiftPMAssessment: Sendable, Equatable, Codable {
    public enum Outcome: String, Sendable, Equatable, Codable, CaseIterable {
        case declarationCompatible
        case requiresGeneratedMetadata
        case indeterminate
        case unsupported
    }

    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let cocoaPodsProfile: CocoaPodsSemanticProfile
    public let swiftPMProfile: SwiftPMCapabilityProfile
    public let outcome: Outcome
    public let reasons: [PodspecSwiftPMAssessmentReason]

    fileprivate init(
        cocoaPodsProfile: CocoaPodsSemanticProfile,
        swiftPMProfile: SwiftPMCapabilityProfile,
        reasons: [PodspecSwiftPMAssessmentReason]
    ) {
        let fallbackReasons = [PodspecSwiftPMAssessmentReason(
            code: .incompleteModeledSemantic,
            evidencePath: ""
        )]
        let canonicalReasons = Self.canonicalReasons(reasons) ?? fallbackReasons
        self.schemaVersion = Self.schemaVersion
        self.cocoaPodsProfile = cocoaPodsProfile
        self.swiftPMProfile = swiftPMProfile
        self.outcome = Self.outcome(for: canonicalReasons)
        self.reasons = canonicalReasons
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case cocoaPodsProfile
        case swiftPMProfile
        case outcome
        case reasons
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.schemaVersion else {
            throw PodspecSwiftPMAssessmentError.unsupportedAssessmentSchemaVersion(
                schemaVersion
            )
        }

        let cocoaPodsProfile = try container.decode(
            CocoaPodsSemanticProfile.self,
            forKey: .cocoaPodsProfile
        )
        guard cocoaPodsProfile == .cocoaPodsCore1_17_0 else {
            throw PodspecSwiftPMAssessmentError.unsupportedCocoaPodsSemanticProfile(
                identifier: cocoaPodsProfile.identifier
            )
        }

        let swiftPMProfile = try container.decode(
            SwiftPMCapabilityProfile.self,
            forKey: .swiftPMProfile
        )
        guard swiftPMProfile == .swiftToolsVersion6_0 else {
            throw PodspecSwiftPMAssessmentError.unsupportedSwiftPMCapabilityProfile(
                identifier: swiftPMProfile.identifier
            )
        }

        let outcome = try container.decode(Outcome.self, forKey: .outcome)
        let reasons = try container.decode(
            [PodspecSwiftPMAssessmentReason].self,
            forKey: .reasons
        )

        guard let canonicalReasons = Self.canonicalReasons(reasons),
              canonicalReasons == reasons,
              Self.outcome(for: reasons) == outcome else {
            throw PodspecSwiftPMAssessmentError.invalidAssessmentContract
        }

        self.schemaVersion = schemaVersion
        self.cocoaPodsProfile = cocoaPodsProfile
        self.swiftPMProfile = swiftPMProfile
        self.outcome = outcome
        self.reasons = reasons
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(cocoaPodsProfile, forKey: .cocoaPodsProfile)
        try container.encode(swiftPMProfile, forKey: .swiftPMProfile)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(reasons, forKey: .reasons)
    }
}

/// Typed profile failures raised before any capability comparison is performed.
public enum PodspecSwiftPMAssessmentError: Swift.Error, LocalizedError, Sendable, Equatable {
    case unsupportedAssessmentSchemaVersion(Int)
    case unsupportedCocoaPodsSemanticProfile(identifier: String)
    case cocoaPodsSemanticProfileMismatch(requested: String, inspected: String)
    case unsupportedSwiftPMCapabilityProfile(identifier: String)
    case invalidAssessmentContract

    public var errorDescription: String? {
        switch self {
        case .unsupportedAssessmentSchemaVersion(let version):
            return "Unsupported Podspec SwiftPM assessment schema version: \(version)."
        case .unsupportedCocoaPodsSemanticProfile(let identifier):
            return "Unsupported CocoaPods semantic profile for assessment: \(identifier)."
        case .cocoaPodsSemanticProfileMismatch(let requested, let inspected):
            return "Requested CocoaPods semantic profile \(requested) does not match inspected profile \(inspected)."
        case .unsupportedSwiftPMCapabilityProfile(let identifier):
            return "Unsupported SwiftPM capability profile: \(identifier)."
        case .invalidAssessmentContract:
            return "Podspec SwiftPM assessment is not canonical for its declared outcome."
        }
    }
}

/// Pure, offline declaration assessment over an already materialized `PodspecInspection`.
///
/// The assessor never reads the filesystem or environment, starts a process, resolves a
/// package, contacts a repository or network service, or mutates project state.
public struct PodspecSwiftPMAssessor: Sendable {
    public init() {}

    public func assess(
        _ inspection: PodspecInspection,
        cocoaPodsProfile: CocoaPodsSemanticProfile,
        swiftPMProfile: SwiftPMCapabilityProfile
    ) throws -> PodspecSwiftPMAssessment {
        guard cocoaPodsProfile == .cocoaPodsCore1_17_0 else {
            throw PodspecSwiftPMAssessmentError.unsupportedCocoaPodsSemanticProfile(
                identifier: cocoaPodsProfile.identifier
            )
        }
        guard inspection.podspec.semanticProfile == cocoaPodsProfile else {
            throw PodspecSwiftPMAssessmentError.cocoaPodsSemanticProfileMismatch(
                requested: cocoaPodsProfile.identifier,
                inspected: inspection.podspec.semanticProfile.identifier
            )
        }
        guard swiftPMProfile == .swiftToolsVersion6_0 else {
            throw PodspecSwiftPMAssessmentError.unsupportedSwiftPMCapabilityProfile(
                identifier: swiftPMProfile.identifier
            )
        }

        var accumulator = AssessmentAccumulator()
        accumulator.inspectModelBoundary(inspection.podspec)

        for (index, field) in inspection.unsupportedFields.enumerated() {
            guard isValidNonRootJSONPointer(field.path) else {
                accumulator.add(
                    .incompleteModeledSemantic,
                    path: ""
                )
                continue
            }
            let evidencePath = PodspecJSONPointer.appending(
                String(index),
                to: "/unsupportedFields"
            )
            switch field.kind {
            case .unknownField:
                accumulator.add(
                    .unknownCocoaPodsSemantic,
                    path: evidencePath
                )
            case .deferredCocoaPodsSemantic:
                accumulator.add(
                    .deferredCocoaPodsSemantic,
                    path: evidencePath
                )
            }
        }

        accumulator.inspectNode(
            inspection.podspec.root,
            expectedPath: "",
            parentName: nil,
            isRoot: true
        )

        return PodspecSwiftPMAssessment(
            cocoaPodsProfile: cocoaPodsProfile,
            swiftPMProfile: swiftPMProfile,
            reasons: accumulator.sortedReasons
        )
    }
}

private enum AssessmentDowngrade: Int {
    case requiresGeneratedMetadata = 1
    case indeterminate = 2
    case unsupported = 3

    var outcome: PodspecSwiftPMAssessment.Outcome {
        switch self {
        case .requiresGeneratedMetadata:
            return .requiresGeneratedMetadata
        case .indeterminate:
            return .indeterminate
        case .unsupported:
            return .unsupported
        }
    }
}

private extension PodspecSwiftPMAssessmentReason.Code {
    var downgrade: AssessmentDowngrade {
        switch self {
        case .platformRequiresGeneratedMetadata,
             .defaultSubspecRequiresGeneratedMetadata,
             .sourceSelectionRequiresGeneratedMetadata,
             .headerSelectionRequiresGeneratedMetadata,
             .resourceSelectionRequiresGeneratedMetadata,
             .resourceBundleRequiresGeneratedMetadata,
             .dependencyRequiresGeneratedMetadata,
             .linkerSettingRequiresGeneratedMetadata,
             .moduleNameRequiresGeneratedMetadata,
             .generatedModuleMapRequiresGeneratedMetadata,
             .headerLayoutRequiresGeneratedMetadata,
             .linkageModeRequiresGeneratedMetadata,
             .fileExclusionRequiresGeneratedMetadata:
            return .requiresGeneratedMetadata
        case .incompleteModeledSemantic,
             .unknownCocoaPodsSemantic,
             .deferredCocoaPodsSemantic,
             .platformScopeSemanticsIndeterminate,
             .subspecSemanticsIndeterminate,
             .vendoredArtifactRequiresInspection,
             .customModuleMapRequiresInspection,
             .swiftVersionRequiresInspection:
            return .indeterminate
        case .weakFrameworkLinkageUnsupported,
             .disabledModuleMapUnsupported,
             .compilerFlagsUnsupported,
             .buildSettingsUnsupported,
             .configurationSpecificDependencyUnsupported,
             .arcControlUnsupported,
             .preservePathUnsupported:
            return .unsupported
        }
    }
}

private extension PodspecSwiftPMAssessment {
    static func outcome(
        for reasons: [PodspecSwiftPMAssessmentReason]
    ) -> Outcome {
        reasons.map { $0.code.downgrade }
            .max(by: { $0.rawValue < $1.rawValue })?.outcome
            ?? .declarationCompatible
    }

    static func canonicalReasons(
        _ reasons: [PodspecSwiftPMAssessmentReason]
    ) -> [PodspecSwiftPMAssessmentReason]? {
        guard reasons.allSatisfy(isValidAssessmentReason) else { return nil }

        let uniqueReasons = Set(reasons)
        return uniqueReasons.sorted { lhs, rhs in
            if lhs.code.downgrade.rawValue != rhs.code.downgrade.rawValue {
                return lhs.code.downgrade.rawValue > rhs.code.downgrade.rawValue
            }
            if lhs.code.rawValue != rhs.code.rawValue {
                return lhs.code.rawValue < rhs.code.rawValue
            }
            return lhs.evidencePath < rhs.evidencePath
        }
    }
}

private func isValidAssessmentReason(_ reason: PodspecSwiftPMAssessmentReason) -> Bool {
    let path = reason.evidencePath
    if path.isEmpty {
        return reason.code == .incompleteModeledSemantic
    }
    return isValidNonRootJSONPointer(path)
}

private func isValidNonRootJSONPointer(_ path: String) -> Bool {
    guard path.first == "/" else { return false }

    var searchStart = path.startIndex
    while let tilde = path[searchStart...].firstIndex(of: "~") {
        let escaped = path.index(after: tilde)
        guard escaped < path.endIndex,
              path[escaped] == "0" || path[escaped] == "1" else {
            return false
        }
        searchStart = path.index(after: escaped)
    }
    return true
}

private struct AssessmentAccumulator {
    private var reasons: Set<PodspecSwiftPMAssessmentReason> = []

    var sortedReasons: [PodspecSwiftPMAssessmentReason] {
        reasons.sorted { lhs, rhs in
            if lhs.code.downgrade.rawValue != rhs.code.downgrade.rawValue {
                return lhs.code.downgrade.rawValue > rhs.code.downgrade.rawValue
            }
            if lhs.code.rawValue != rhs.code.rawValue {
                return lhs.code.rawValue < rhs.code.rawValue
            }
            return lhs.evidencePath < rhs.evidencePath
        }
    }

    mutating func add(
        _ code: PodspecSwiftPMAssessmentReason.Code,
        path: String
    ) {
        let candidate = PodspecSwiftPMAssessmentReason(code: code, evidencePath: path)
        guard isValidAssessmentReason(candidate) else {
            reasons.insert(PodspecSwiftPMAssessmentReason(
                code: .incompleteModeledSemantic,
                evidencePath: ""
            ))
            return
        }

        reasons.insert(candidate)
    }

    mutating func inspectModelBoundary(_ model: PodspecSemanticModel) {
        if model.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !Self.isValidIdentityName(model.root.baseName)
            || model.root.name != model.root.baseName
            || model.root.path != "" {
            add(.incompleteModeledSemantic, path: "")
        }
    }

    mutating func inspectNode(
        _ node: PodspecNode,
        expectedPath: String,
        parentName: String?,
        isRoot: Bool
    ) {
        let expectedName = parentName.map { "\($0)/\(node.baseName)" } ?? node.baseName
        if node.path != expectedPath
            || node.name != expectedName
            || !Self.isValidIdentityName(node.baseName) {
            add(.incompleteModeledSemantic, path: "")
        }

        let platformKeys = node.platforms.map { Self.platformJSONKey($0.platform) }
        let sortedPlatformKeys = node.platforms
            .sorted { Self.platformRank($0.platform) < Self.platformRank($1.platform) }
            .map { Self.platformJSONKey($0.platform) }
        if platformKeys != sortedPlatformKeys
            || Set(platformKeys).count != platformKeys.count
            || node.platforms.contains(where: {
                $0.minimumVersion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    == true
            }) {
            add(
                .incompleteModeledSemantic,
                path: Self.path("platforms", beneath: expectedPath)
            )
        }
        for platform in node.platforms {
            add(
                .platformRequiresGeneratedMetadata,
                path: Self.platformRequirementPath(platform.platform, beneath: expectedPath)
            )
        }

        inspectDefaultSubspecSelection(
            node.defaultSubspecs,
            nodePath: expectedPath,
            isRoot: isRoot,
            hasSubspecs: !node.subspecs.isEmpty
        )

        inspectDeclarations(node.declarations, beneath: expectedPath)

        for scope in node.platformScopes {
            let scopePath = Self.path(
                Self.platformJSONKey(scope.platform),
                beneath: expectedPath
            )
            if scope.path != scopePath {
                add(.incompleteModeledSemantic, path: "")
            }
            add(
                .platformScopeSemanticsIndeterminate,
                path: scopePath
            )
            inspectDeclarations(scope.declarations, beneath: scopePath)
        }

        for (index, subspec) in node.subspecs.enumerated() {
            let subspecPath = Self.path(
                String(index),
                beneath: Self.path("subspecs", beneath: expectedPath)
            )
            add(
                .subspecSemanticsIndeterminate,
                path: subspecPath
            )
            inspectNode(
                subspec,
                expectedPath: subspecPath,
                parentName: expectedName,
                isRoot: false
            )
        }
    }

    mutating func inspectDefaultSubspecSelection(
        _ selection: PodspecDefaultSubspecSelection,
        nodePath: String,
        isRoot: Bool,
        hasSubspecs: Bool
    ) {
        let singularPath = Self.path("default_subspec", beneath: nodePath)
        let pluralPath = Self.path("default_subspecs", beneath: nodePath)
        let safeDeclarationPath: String
        if let declarationPath = selection.declarationPath {
            guard declarationPath == singularPath || declarationPath == pluralPath else {
                add(.incompleteModeledSemantic, path: pluralPath)
                return
            }
            safeDeclarationPath = declarationPath
        } else {
            safeDeclarationPath = pluralPath
        }

        if !isRoot && (
            selection.kind != .all
                || selection.declarationPath != nil
                || selection.valuePath != nil
                || !selection.references.isEmpty
        ) {
            add(.incompleteModeledSemantic, path: pluralPath)
            return
        }

        switch selection.kind {
        case .all:
            let isImplicit = selection.declarationPath == nil
                && selection.valuePath == nil
                && selection.references.isEmpty
            let isExplicitEmpty = selection.declarationPath == pluralPath
                && selection.valuePath == pluralPath
                && selection.references.isEmpty
            guard isImplicit || isExplicitEmpty else {
                add(
                    .incompleteModeledSemantic,
                    path: safeDeclarationPath
                )
                return
            }
        case .none:
            let valuePathIsValid = selection.valuePath == safeDeclarationPath
                || (safeDeclarationPath == pluralPath
                    && selection.valuePath == Self.path("0", beneath: pluralPath))
            guard selection.declarationPath != nil,
                  valuePathIsValid,
                  selection.references.isEmpty else {
                add(
                    .incompleteModeledSemantic,
                    path: safeDeclarationPath
                )
                return
            }
        case .named:
            guard selection.declarationPath != nil,
                  selection.valuePath == nil,
                  !selection.references.isEmpty,
                  safeDeclarationPath != singularPath || selection.references.count == 1,
                  hasSubspecs else {
                add(
                    .incompleteModeledSemantic,
                    path: safeDeclarationPath
                )
                return
            }
            for (index, reference) in selection.references.enumerated() {
                let indexedPath = Self.path(String(index), beneath: safeDeclarationPath)
                let sourcePathIsValid = reference.path == indexedPath
                    || (selection.references.count == 1
                        && reference.path == safeDeclarationPath)
                if !sourcePathIsValid
                    || reference.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || reference.resolvedName
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    add(
                        .incompleteModeledSemantic,
                        path: Self.indexedPath(
                            index,
                            field: "default_subspecs",
                            beneath: nodePath
                        )
                    )
                }
            }
        }

        if selection.declarationPath != nil {
            add(
                .defaultSubspecRequiresGeneratedMetadata,
                path: safeDeclarationPath
            )
        }
    }

    mutating func inspectDeclarations(
        _ declarations: PodspecScopedDeclarations,
        beneath scopePath: String
    ) {
        if !declarations.sourceFiles.isEmpty {
            add(
                .sourceSelectionRequiresGeneratedMetadata,
                path: Self.path("source_files", beneath: scopePath)
            )
            inspectNonEmptyStrings(
                declarations.sourceFiles,
                field: "source_files",
                beneath: scopePath
            )
        }
        if !declarations.publicHeaders.isEmpty {
            add(
                .headerSelectionRequiresGeneratedMetadata,
                path: Self.path("public_header_files", beneath: scopePath)
            )
            inspectNonEmptyStrings(
                declarations.publicHeaders,
                field: "public_header_files",
                beneath: scopePath
            )
        }
        if !declarations.privateHeaders.isEmpty {
            add(
                .headerSelectionRequiresGeneratedMetadata,
                path: Self.path("private_header_files", beneath: scopePath)
            )
            inspectNonEmptyStrings(
                declarations.privateHeaders,
                field: "private_header_files",
                beneath: scopePath
            )
        }
        if !declarations.resources.isEmpty {
            add(
                .resourceSelectionRequiresGeneratedMetadata,
                path: Self.path("resources", beneath: scopePath)
            )
            inspectNonEmptyStrings(
                declarations.resources,
                field: "resources",
                beneath: scopePath
            )
        }
        if !declarations.resourceBundles.isEmpty {
            add(
                .resourceBundleRequiresGeneratedMetadata,
                path: Self.path("resource_bundles", beneath: scopePath)
            )
            for (index, bundle) in declarations.resourceBundles.enumerated()
            where bundle.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || bundle.resources.contains(where: {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }) {
                add(
                    .incompleteModeledSemantic,
                    path: Self.indexedPath(
                        index,
                        field: "resource_bundles",
                        beneath: scopePath
                    )
                )
            }
            let bundleNames = declarations.resourceBundles.map(\.name)
            if bundleNames != bundleNames.sorted()
                || Set(bundleNames).count != bundleNames.count {
                add(
                    .incompleteModeledSemantic,
                    path: Self.path("resource_bundles", beneath: scopePath)
                )
            }
        }
        let dependencyNames = declarations.dependencies.map(\.name)
        if dependencyNames != dependencyNames.sorted()
            || Set(dependencyNames).count != dependencyNames.count {
            add(
                .incompleteModeledSemantic,
                path: Self.path("dependencies", beneath: scopePath)
            )
        }
        for (index, dependency) in declarations.dependencies.enumerated() {
            let evidencePath = Self.indexedPath(
                index,
                field: "dependencies",
                beneath: scopePath
            )
            let sourcePath = Self.path(
                dependency.name,
                beneath: Self.path("dependencies", beneath: scopePath)
            )
            add(
                .dependencyRequiresGeneratedMetadata,
                path: evidencePath
            )
            let requirementsAreValid = dependency.requirements.enumerated().allSatisfy {
                requirementIndex, requirement in
                requirement.path == Self.path(String(requirementIndex), beneath: sourcePath)
                    && !requirement.literal
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if dependency.path != sourcePath
                || dependency.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !requirementsAreValid {
                add(.incompleteModeledSemantic, path: evidencePath)
            }
        }

        inspectLinkage(declarations.linkage, beneath: scopePath)
        inspectCompilation(
            declarations.compilation,
            beneath: scopePath,
            dependencyNames: Set(dependencyNames)
        )
    }

    mutating func inspectLinkage(
        _ linkage: PodspecLinkageDeclarations,
        beneath scopePath: String
    ) {
        addLiteralReasons(
            linkage.frameworks,
            field: "frameworks",
            beneath: scopePath,
            code: .linkerSettingRequiresGeneratedMetadata
        )
        addLiteralReasons(
            linkage.libraries,
            field: "libraries",
            beneath: scopePath,
            code: .linkerSettingRequiresGeneratedMetadata
        )
        addLiteralReasons(
            linkage.weakFrameworks,
            field: "weak_frameworks",
            beneath: scopePath,
            code: .weakFrameworkLinkageUnsupported
        )
        addLiteralReasons(
            linkage.vendoredFrameworks,
            field: "vendored_frameworks",
            beneath: scopePath,
            code: .vendoredArtifactRequiresInspection
        )
        addLiteralReasons(
            linkage.vendoredLibraries,
            field: "vendored_libraries",
            beneath: scopePath,
            code: .vendoredArtifactRequiresInspection
        )
        if let declaration = linkage.moduleName {
            let evidencePath = Self.path("module_name", beneath: scopePath)
            add(
                .moduleNameRequiresGeneratedMetadata,
                path: evidencePath
            )
            inspectLiteral(
                declaration,
                evidencePath: evidencePath,
                sourcePathIsValid: declaration.path == evidencePath
            )
        }
        if let declaration = linkage.moduleMap {
            let evidencePath = Self.path("module_map", beneath: scopePath)
            if declaration.path != evidencePath {
                add(.incompleteModeledSemantic, path: evidencePath)
            }
            switch declaration.value {
            case .generated:
                add(
                    .generatedModuleMapRequiresGeneratedMetadata,
                    path: evidencePath
                )
            case .customPath(let literal):
                add(
                    .customModuleMapRequiresInspection,
                    path: evidencePath
                )
                if literal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    add(.incompleteModeledSemantic, path: evidencePath)
                }
            case .disabled:
                add(
                    .disabledModuleMapUnsupported,
                    path: evidencePath
                )
            }
        }
        if let declaration = linkage.headerDirectory {
            let evidencePath = Self.path("header_dir", beneath: scopePath)
            add(
                .headerLayoutRequiresGeneratedMetadata,
                path: evidencePath
            )
            inspectLiteral(
                declaration,
                evidencePath: evidencePath,
                sourcePathIsValid: declaration.path == evidencePath
            )
        }
        if let declaration = linkage.headerMappingsDirectory {
            let evidencePath = Self.path("header_mappings_dir", beneath: scopePath)
            add(.headerLayoutRequiresGeneratedMetadata, path: evidencePath)
            inspectLiteral(
                declaration,
                evidencePath: evidencePath,
                sourcePathIsValid: declaration.path == evidencePath
            )
        }
        addLiteralReasons(
            linkage.projectHeaders,
            field: "project_header_files",
            beneath: scopePath,
            code: .headerLayoutRequiresGeneratedMetadata
        )
        if let declaration = linkage.staticFramework {
            let evidencePath = Self.path("static_framework", beneath: scopePath)
            add(
                .linkageModeRequiresGeneratedMetadata,
                path: evidencePath
            )
            if declaration.path != evidencePath {
                add(.incompleteModeledSemantic, path: evidencePath)
            }
        }
    }

    mutating func inspectCompilation(
        _ compilation: PodspecCompilationDeclarations,
        beneath scopePath: String,
        dependencyNames: Set<String>
    ) {
        addLiteralReasons(
            compilation.compilerFlags,
            field: "compiler_flags",
            beneath: scopePath,
            code: .compilerFlagsUnsupported
        )
        inspectBuildSettings(
            compilation.legacyXCConfig,
            field: "xcconfig",
            beneath: scopePath
        )
        inspectBuildSettings(
            compilation.podTargetXCConfig,
            field: "pod_target_xcconfig",
            beneath: scopePath
        )
        inspectBuildSettings(
            compilation.userTargetXCConfig,
            field: "user_target_xcconfig",
            beneath: scopePath
        )
        let whitelistNames = compilation.configurationPodWhitelist.map(\.podName)
        if whitelistNames != whitelistNames.sorted()
            || Set(whitelistNames).count != whitelistNames.count {
            add(
                .incompleteModeledSemantic,
                path: Self.path("configuration_pod_whitelist", beneath: scopePath)
            )
        }
        for (index, declaration) in compilation.configurationPodWhitelist.enumerated() {
            let evidencePath = Self.indexedPath(
                index,
                field: "configuration_pod_whitelist",
                beneath: scopePath
            )
            let sourcePath = Self.path(
                declaration.podName,
                beneath: Self.path("configuration_pod_whitelist", beneath: scopePath)
            )
            add(
                .configurationSpecificDependencyUnsupported,
                path: evidencePath
            )
            let configurationsAreValid = declaration.configurations.enumerated().allSatisfy {
                configurationIndex, configuration in
                configuration.path == Self.path(String(configurationIndex), beneath: sourcePath)
                    && (configuration.literal == "debug"
                        || configuration.literal == "release")
            }
            if declaration.path != sourcePath
                || declaration.podName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !dependencyNames.contains(declaration.podName)
                || !configurationsAreValid {
                add(.incompleteModeledSemantic, path: evidencePath)
            }
        }

        let swiftVersions = compilation.swiftVersions
        let pluralPath = Self.path("swift_versions", beneath: scopePath)
        let singularPath = Self.path("swift_version", beneath: scopePath)
        let hasPlural = swiftVersions.pluralDeclarationPath != nil
        let hasSingular = swiftVersions.legacySingular != nil
        let canProveExactPair: Bool
        if let singular = swiftVersions.legacySingular {
            canProveExactPair = !swiftVersions.versions.isEmpty
                && swiftVersions.versions.allSatisfy { $0.literal == singular.literal }
        } else {
            canProveExactPair = false
        }
        let relationshipIsConsistent: Bool
        switch swiftVersions.relationship {
        case .notApplicable:
            relationshipIsConsistent = !(hasPlural && hasSingular)
        case .exactMatch:
            relationshipIsConsistent = hasPlural && hasSingular && canProveExactPair
        case .requiresCocoaPodsNormalization:
            relationshipIsConsistent = hasPlural && hasSingular && !canProveExactPair
        }
        let versionsAreComplete = swiftVersions.versions.enumerated().allSatisfy {
            index, declaration in
            let indexedPath = Self.path(String(index), beneath: pluralPath)
            let pathIsValid = declaration.path == indexedPath
                || (swiftVersions.versions.count == 1 && declaration.path == pluralPath)
            return pathIsValid
                && !declaration.literal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let declarationsAreComplete = (swiftVersions.versions.isEmpty || hasPlural)
            && (swiftVersions.pluralDeclarationPath == nil
                || swiftVersions.pluralDeclarationPath == pluralPath)
            && versionsAreComplete
            && (swiftVersions.legacySingular.map {
                $0.path == singularPath
                    && !$0.literal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? true)
        if !relationshipIsConsistent || !declarationsAreComplete {
            add(
                .incompleteModeledSemantic,
                path: pluralPath
            )
        }
        for (index, _) in swiftVersions.versions.enumerated() {
            add(
                .swiftVersionRequiresInspection,
                path: Self.indexedPath(
                    index,
                    field: "swift_versions",
                    beneath: scopePath
                )
            )
        }
        if swiftVersions.versions.isEmpty,
           swiftVersions.pluralDeclarationPath != nil {
            add(
                .swiftVersionRequiresInspection,
                path: pluralPath
            )
        }
        if swiftVersions.legacySingular != nil {
            add(
                .swiftVersionRequiresInspection,
                path: singularPath
            )
        }
        if let requiresARC = compilation.requiresARC {
            let evidencePath = Self.path("requires_arc", beneath: scopePath)
            add(.arcControlUnsupported, path: evidencePath)
            var sourceIsValid = requiresARC.path == evidencePath
            if case .filePatterns(let declarations) = requiresARC.value {
                sourceIsValid = sourceIsValid
                    && declarations.enumerated().allSatisfy { index, declaration in
                        let indexedPath = Self.path(String(index), beneath: evidencePath)
                        let pathIsValid = declaration.path == indexedPath
                            || (declarations.count == 1
                                && declaration.path == evidencePath)
                        return pathIsValid
                            && !declaration.literal
                                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
            }
            if !sourceIsValid {
                add(.incompleteModeledSemantic, path: evidencePath)
            }
        }
        addLiteralReasons(
            compilation.excludeFiles,
            field: "exclude_files",
            beneath: scopePath,
            code: .fileExclusionRequiresGeneratedMetadata
        )
        addLiteralReasons(
            compilation.preservePaths,
            field: "preserve_paths",
            beneath: scopePath,
            code: .preservePathUnsupported
        )
    }

    mutating func inspectNonEmptyStrings(
        _ values: [String],
        field: String,
        beneath scopePath: String
    ) {
        for (index, value) in values.enumerated()
        where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(
                .incompleteModeledSemantic,
                path: Self.indexedPath(index, field: field, beneath: scopePath)
            )
        }
    }

    mutating func addLiteralReasons(
        _ declarations: [PodspecLiteralDeclaration],
        field: String,
        beneath scopePath: String,
        code: PodspecSwiftPMAssessmentReason.Code
    ) {
        for (index, declaration) in declarations.enumerated() {
            let evidencePath = Self.indexedPath(index, field: field, beneath: scopePath)
            let sourceFieldPath = Self.path(field, beneath: scopePath)
            let indexedSourcePath = Self.path(String(index), beneath: sourceFieldPath)
            let sourcePathIsValid = declaration.path == indexedSourcePath
                || (declarations.count == 1 && declaration.path == sourceFieldPath)
            add(code, path: evidencePath)
            inspectLiteral(
                declaration,
                evidencePath: evidencePath,
                sourcePathIsValid: sourcePathIsValid
            )
        }
    }

    mutating func inspectBuildSettings(
        _ declarations: [PodspecBuildSettingDeclaration],
        field: String,
        beneath scopePath: String
    ) {
        let keys = declarations.map(\.key)
        if keys != keys.sorted() || Set(keys).count != keys.count {
            add(
                .incompleteModeledSemantic,
                path: Self.path(field, beneath: scopePath)
            )
        }
        for (index, declaration) in declarations.enumerated() {
            let evidencePath = Self.indexedPath(index, field: field, beneath: scopePath)
            let sourcePath = Self.path(
                declaration.key,
                beneath: Self.path(field, beneath: scopePath)
            )
            add(.buildSettingsUnsupported, path: evidencePath)
            if declaration.path != sourcePath
                || declaration.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                add(.incompleteModeledSemantic, path: evidencePath)
            }
        }
    }

    mutating func inspectLiteral(
        _ declaration: PodspecLiteralDeclaration,
        evidencePath: String,
        sourcePathIsValid: Bool
    ) {
        if !sourcePathIsValid
            || declaration.literal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.incompleteModeledSemantic, path: evidencePath)
        }
    }

    private static func path(_ component: String, beneath path: String) -> String {
        PodspecJSONPointer.appending(component, to: path)
    }

    private static func indexedPath(
        _ index: Int,
        field: String,
        beneath path: String
    ) -> String {
        Self.path(String(index), beneath: Self.path(field, beneath: path))
    }

    private static func platformRequirementPath(
        _ platform: PodspecPlatform,
        beneath path: String
    ) -> String {
        Self.path(platformJSONKey(platform), beneath: Self.path("platforms", beneath: path))
    }

    private static func platformJSONKey(_ platform: PodspecPlatform) -> String {
        switch platform {
        case .iOS:
            return "ios"
        case .macOS:
            return "osx"
        case .tvOS:
            return "tvos"
        case .watchOS:
            return "watchos"
        case .visionOS:
            return "visionos"
        }
    }

    private static func platformRank(_ platform: PodspecPlatform) -> Int {
        switch platform {
        case .iOS:
            return 0
        case .macOS:
            return 1
        case .tvOS:
            return 2
        case .watchOS:
            return 3
        case .visionOS:
            return 4
        }
    }

    private static func isValidIdentityName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !name.hasPrefix(".")
            && !name.contains("/")
            && !name.contains(where: \Character.isWhitespace)
    }

}
