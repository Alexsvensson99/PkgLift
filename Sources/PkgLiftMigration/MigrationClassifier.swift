//
//  MigrationClassifier.swift
//  PkgLiftMigration
//

import Foundation
import PkgLiftCore
import PkgLiftCocoaPods

/// Backward-compatible classification category for migration decisions.
public typealias MigrationCategory = PkgLiftCore.MigrationClassification

public struct MigrationClassification: Sendable, Equatable {
    public let category: MigrationCategory
    public let reason: String
    public let reasons: [String]
    
    public init(category: MigrationCategory, reason: String) {
        self.category = category
        self.reason = reason
        self.reasons = [reason]
    }

    public init(category: MigrationCategory, reasons: [String]) {
        let stableReasons = deduplicated(reasons)
        self.category = category
        self.reason = stableReasons.first ?? "No classification reason available"
        self.reasons = stableReasons
    }
}

/// Classifies each CocoaPod dependency.
public struct MigrationClassifier: Sendable {
    
    public init() {}
    
    public func classify(
        dependency: CocoaPodDependency,
        mapping: RegistryMapping?,
        isAlreadyMigrated: Bool = false,
        isTargetMappingKnown: Bool = true,
        podfileFeatures: PodfileFeatures = PodfileFeatures()
    ) -> MigrationClassification {
        let dependencyInfo = DependencyInfo(
            identifier: dependency.name,
            isDirect: dependency.isDirect,
            isExternalSource: {
                switch dependency.source {
                case .git, .path:
                    return true
                case .registry, .unknown:
                    return false
                }
            }(),
            hasUnrepresentableDeclaration: dependency.source == .unknown,
            hasLiteralDeclarationProvenance: dependency.hasLiteralMigrationProvenance,
            hasPreInstallHooks: podfileFeatures.hasPreInstallHook,
            hasPostInstallHooks: podfileFeatures.hasPostInstallHook,
            hasScriptPhase: podfileFeatures.hasScriptPhase,
            hasDynamicLogic: podfileFeatures.hasDynamicRuby,
            useFrameworks: podfileFeatures.useFrameworks,
            hasInheritSearchPaths: podfileFeatures.hasInheritSearchPaths,
            hasAbstractTargets: podfileFeatures.hasAbstractTargets,
            targetCount: dependency.targets.count,
            targetAttributionStatus: dependency.effectiveTargetAttribution.status,
            targetAttributionReason: dependency.effectiveTargetAttribution.reason,
            versionConstraint: dependency.version,
            resolvedVersion: dependency.version
        )
        
        let mappingInfo = mapping.map {
            RegistryMappingInfo(
                identifier: $0.pod.fullName,
                confidence: $0.migration.confidence,
                repositoryURL: $0.swiftpm.repository,
                products: $0.swiftpm.products,
                minimumVersion: $0.swiftpm.minimumVersion
            )
        }
        
        return classify(dependency: dependencyInfo, mapping: mappingInfo, isAlreadyMigrated: isAlreadyMigrated, isTargetMappingKnown: isTargetMappingKnown)
    }

    private func classify(
        dependency: DependencyInfo,
        mapping: RegistryMappingInfo?,
        isAlreadyMigrated: Bool = false,
        isTargetMappingKnown: Bool = true
    ) -> MigrationClassification {
        var reasons: [String] = []

        if mapping == nil {
            if dependency.isExternalSource {
                reasons.append("External source without mapping")
                reasons.append("No registry mapping")
            } else {
                reasons.append("No registry mapping")
            }
        } else if mapping?.identifier != dependency.identifier {
            reasons.append("Registry mapping identifier does not exactly match dependency")
        }

        if !dependency.isDirect {
            reasons.append("Transitive dependency is not a removable Podfile declaration")
        }

        if dependency.hasUnrepresentableDeclaration {
            reasons.append("Podfile declaration source, options, or expressions cannot be represented safely")
        }

        if mapping != nil, dependency.isDirect, !dependency.hasLiteralDeclarationProvenance {
            reasons.append("Literal Podfile declaration provenance is missing or inconsistent")
        }

        if dependency.isExternalSource, mapping != nil {
            reasons.append("External dependency source requires manual review")
        }

        if let mapping,
           mapping.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || mapping.products.isEmpty
            || !mapping.products.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            reasons.append("Registry mapping lacks an executable package URL or product")
        }

        if dependency.hasPreInstallHooks || dependency.hasPostInstallHooks {
            reasons.append("Podfile install hook detected")
        }
        if dependency.hasScriptPhase {
            reasons.append("Podfile script_phase detected")
        }
        if dependency.hasDynamicLogic {
            reasons.append("Dynamic Podfile logic detected")
        }
        if dependency.useFrameworks {
            reasons.append("use_frameworks! detected")
        }
        if dependency.hasInheritSearchPaths {
            reasons.append("inherit! :search_paths detected")
        }
        if dependency.hasAbstractTargets {
            reasons.append("abstract_target detected")
        }

        if let mapping, mapping.confidence != .verified {
            reasons.append("Registry mapping is not verified")
        }

        switch dependency.targetAttributionStatus {
        case .exact:
            if !isTargetMappingKnown || dependency.targetCount != 1 {
                reasons.append("Podfile target does not match exactly one existing Xcode target")
            }
        case .multiple:
            reasons.append(dependency.targetAttributionReason ?? "Multiple Podfile targets are proven")
        case .partial:
            reasons.append(dependency.targetAttributionReason ?? "Target attribution is partial")
        case .unresolved:
            reasons.append(dependency.targetAttributionReason ?? "Target is unresolved from static Podfile structure")
        }

        let resolvedVersion: SemanticVersion?
        if let resolvedVersionText = dependency.resolvedVersion,
           let parsed = SemanticVersion(rawValue: resolvedVersionText) {
            resolvedVersion = parsed
        } else {
            resolvedVersion = nil
            reasons.append("Resolved version is missing or is not stable major.minor.patch")
        }

        var minimumVersion: SemanticVersion?
        if let mapping {
            if let minimumVersionText = mapping.minimumVersion {
                if let parsed = SemanticVersion(rawValue: minimumVersionText) {
                    minimumVersion = parsed
                } else {
                    minimumVersion = nil
                    reasons.append("Registry mapping minimum SwiftPM version is invalid")
                }
            } else {
                minimumVersion = nil
                reasons.append("Registry mapping has no verified minimum SwiftPM version")
            }
        }

        if let resolvedVersion, let minimumVersion, resolvedVersion < minimumVersion {
            reasons.append(
                "Resolved version \(resolvedVersion) predates verified SwiftPM support at \(minimumVersion)"
            )
        }

        if resolvedVersion != nil,
           VersionMapper().map(
                constraint: dependency.versionConstraint ?? "",
                resolvedVersion: dependency.resolvedVersion
           ) == nil {
            reasons.append("Version requirement cannot be represented safely")
        }

        let stableReasons = deduplicated(reasons)
        if stableReasons.isEmpty,
           let resolvedVersion,
           let minimumVersion {
            return MigrationClassification(
                category: .auto,
                reasons: [
                    "Verified exact registry mapping; resolved version \(resolvedVersion) meets minimum \(minimumVersion)",
                ]
            )
        }

        let category: MigrationCategory
        if mapping == nil {
            category = dependency.isExternalSource ? .blocked : .unknown
        } else {
            category = .review
        }
        return MigrationClassification(category: category, reasons: stableReasons)
    }
}

private func deduplicated(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
}

private struct RegistryMappingInfo: Sendable {
    let identifier: String
    let confidence: PkgLiftCore.MigrationConfidence
    let repositoryURL: String
    let products: [String]
    let minimumVersion: String?
}

private struct DependencyInfo: Sendable {
    let identifier: String
    let isDirect: Bool
    let isExternalSource: Bool
    let hasUnrepresentableDeclaration: Bool
    let hasLiteralDeclarationProvenance: Bool
    let hasPreInstallHooks: Bool
    let hasPostInstallHooks: Bool
    let hasScriptPhase: Bool
    let hasDynamicLogic: Bool
    let useFrameworks: Bool
    let hasInheritSearchPaths: Bool
    let hasAbstractTargets: Bool
    let targetCount: Int
    let targetAttributionStatus: TargetAttributionStatus
    let targetAttributionReason: String?
    let versionConstraint: String?
    let resolvedVersion: String?
    
    init(
        identifier: String = "",
        isDirect: Bool = true,
        isExternalSource: Bool = false,
        hasUnrepresentableDeclaration: Bool = false,
        hasLiteralDeclarationProvenance: Bool = false,
        hasPreInstallHooks: Bool = false,
        hasPostInstallHooks: Bool = false,
        hasScriptPhase: Bool = false,
        hasDynamicLogic: Bool = false,
        useFrameworks: Bool = false,
        hasInheritSearchPaths: Bool = false,
        hasAbstractTargets: Bool = false,
        targetCount: Int = 1,
        targetAttributionStatus: TargetAttributionStatus = .exact,
        targetAttributionReason: String? = nil,
        versionConstraint: String? = nil,
        resolvedVersion: String? = nil
    ) {
        self.identifier = identifier
        self.isDirect = isDirect
        self.isExternalSource = isExternalSource
        self.hasUnrepresentableDeclaration = hasUnrepresentableDeclaration
        self.hasLiteralDeclarationProvenance = hasLiteralDeclarationProvenance
        self.hasPreInstallHooks = hasPreInstallHooks
        self.hasPostInstallHooks = hasPostInstallHooks
        self.hasScriptPhase = hasScriptPhase
        self.hasDynamicLogic = hasDynamicLogic
        self.useFrameworks = useFrameworks
        self.hasInheritSearchPaths = hasInheritSearchPaths
        self.hasAbstractTargets = hasAbstractTargets
        self.targetCount = targetCount
        self.targetAttributionStatus = targetAttributionStatus
        self.targetAttributionReason = targetAttributionReason
        self.versionConstraint = versionConstraint
        self.resolvedVersion = resolvedVersion
    }
}
