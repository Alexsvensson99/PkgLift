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
    
    public init(category: MigrationCategory, reason: String) {
        self.category = category
        self.reason = reason
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
            isExternalSource: dependency.source != .registry,
            hasPreInstallHooks: podfileFeatures.hasPreInstallHook,
            hasPostInstallHooks: podfileFeatures.hasPostInstallHook,
            hasScriptPhase: podfileFeatures.hasScriptPhase,
            hasDynamicLogic: podfileFeatures.hasDynamicRuby,
            useFrameworks: podfileFeatures.useFrameworks,
            hasInheritSearchPaths: podfileFeatures.hasInheritSearchPaths,
            hasAbstractTargets: podfileFeatures.hasAbstractTargets,
            targetCount: dependency.targets.count,
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
        guard let mapping else {
            if dependency.isExternalSource {
                return MigrationClassification(category: .blocked, reason: "External source without mapping")
            }
            return MigrationClassification(category: .unknown, reason: "No registry mapping")
        }

        guard mapping.identifier == dependency.identifier else {
            return MigrationClassification(category: .review, reason: "Registry mapping identifier does not exactly match dependency")
        }

        if !dependency.isDirect {
            return MigrationClassification(category: .review, reason: "Transitive dependency is not a removable Podfile declaration")
        }

        if dependency.isExternalSource {
            return MigrationClassification(category: .review, reason: "External dependency source requires manual review")
        }

        guard !mapping.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !mapping.products.isEmpty,
              mapping.products.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return MigrationClassification(category: .review, reason: "Registry mapping lacks an executable package URL or product")
        }
        
        if dependency.hasPreInstallHooks || dependency.hasPostInstallHooks {
            return MigrationClassification(category: .review, reason: "Podfile install hook detected")
        }

        if dependency.hasScriptPhase {
            return MigrationClassification(category: .review, reason: "Podfile script_phase detected")
        }

        if dependency.hasDynamicLogic {
            return MigrationClassification(category: .review, reason: "Dynamic Podfile logic detected")
        }
        
        if dependency.useFrameworks {
            return MigrationClassification(category: .review, reason: "use_frameworks! detected")
        }

        if dependency.hasInheritSearchPaths {
            return MigrationClassification(category: .review, reason: "inherit! :search_paths detected")
        }

        if dependency.hasAbstractTargets {
            return MigrationClassification(category: .review, reason: "abstract_target detected")
        }
        
        guard mapping.confidence == .verified else {
            return MigrationClassification(category: .review, reason: "Registry mapping is not verified")
        }
        
        if !isTargetMappingKnown || dependency.targetCount != 1 {
            return MigrationClassification(category: .review, reason: "Target is ambiguous or mapping unknown")
        }
        
        guard let resolvedVersionText = dependency.resolvedVersion,
              let resolvedVersion = SemanticVersion(rawValue: resolvedVersionText) else {
            return MigrationClassification(category: .review, reason: "Resolved version is missing or is not stable major.minor.patch")
        }

        guard let minimumVersionText = mapping.minimumVersion else {
            return MigrationClassification(category: .review, reason: "Registry mapping has no verified minimum SwiftPM version")
        }

        guard let minimumVersion = SemanticVersion(rawValue: minimumVersionText) else {
            return MigrationClassification(category: .review, reason: "Registry mapping minimum SwiftPM version is invalid")
        }

        guard resolvedVersion >= minimumVersion else {
            return MigrationClassification(
                category: .review,
                reason: "Resolved version \(resolvedVersion) predates verified SwiftPM support at \(minimumVersion)"
            )
        }

        let mapper = VersionMapper()
        guard mapper.map(
            constraint: dependency.versionConstraint ?? "",
            resolvedVersion: dependency.resolvedVersion
        ) != nil else {
            return MigrationClassification(category: .review, reason: "Version requirement cannot be represented safely")
        }
        
        // Deterministic evidence for AUTO
        return MigrationClassification(
            category: .auto,
            reason: "Verified exact registry mapping; resolved version \(resolvedVersion) meets minimum \(minimumVersion)"
        )
    }
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
    let hasPreInstallHooks: Bool
    let hasPostInstallHooks: Bool
    let hasScriptPhase: Bool
    let hasDynamicLogic: Bool
    let useFrameworks: Bool
    let hasInheritSearchPaths: Bool
    let hasAbstractTargets: Bool
    let targetCount: Int
    let versionConstraint: String?
    let resolvedVersion: String?
    
    init(
        identifier: String = "",
        isDirect: Bool = true,
        isExternalSource: Bool = false,
        hasPreInstallHooks: Bool = false,
        hasPostInstallHooks: Bool = false,
        hasScriptPhase: Bool = false,
        hasDynamicLogic: Bool = false,
        useFrameworks: Bool = false,
        hasInheritSearchPaths: Bool = false,
        hasAbstractTargets: Bool = false,
        targetCount: Int = 1,
        versionConstraint: String? = nil,
        resolvedVersion: String? = nil
    ) {
        self.identifier = identifier
        self.isDirect = isDirect
        self.isExternalSource = isExternalSource
        self.hasPreInstallHooks = hasPreInstallHooks
        self.hasPostInstallHooks = hasPostInstallHooks
        self.hasScriptPhase = hasScriptPhase
        self.hasDynamicLogic = hasDynamicLogic
        self.useFrameworks = useFrameworks
        self.hasInheritSearchPaths = hasInheritSearchPaths
        self.hasAbstractTargets = hasAbstractTargets
        self.targetCount = targetCount
        self.versionConstraint = versionConstraint
        self.resolvedVersion = resolvedVersion
    }
}
