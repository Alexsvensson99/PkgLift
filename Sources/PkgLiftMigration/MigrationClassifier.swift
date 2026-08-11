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
            isDirect: dependency.isDirect,
            isExternalSource: dependency.source != .registry,
            hasPreInstallHooks: podfileFeatures.hasPreInstallHook,
            hasPostInstallHooks: podfileFeatures.hasPostInstallHook,
            hasDynamicLogic: podfileFeatures.hasDynamicRuby,
            useFrameworks: podfileFeatures.useFrameworks,
            targetCount: dependency.targets.count,
            versionConstraint: dependency.version,
            resolvedVersion: dependency.version
        )
        
        let mappingInfo = mapping.map {
            RegistryMappingInfo(
                exists: true,
                confidence: $0.migration.confidence,
                repositoryURL: $0.swiftpm.repository,
                products: $0.swiftpm.products
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
        guard let mapping = mapping, mapping.exists else {
            if dependency.isExternalSource {
                return MigrationClassification(category: .blocked, reason: "External source without mapping")
            }
            return MigrationClassification(category: .unknown, reason: "No registry mapping")
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
        
        if dependency.hasPreInstallHooks || dependency.hasPostInstallHooks || dependency.hasDynamicLogic {
            return MigrationClassification(category: .review, reason: "Complex Podfile logic detected")
        }
        
        if dependency.useFrameworks {
            return MigrationClassification(category: .review, reason: "use_frameworks! detected")
        }
        
        if mapping.confidence == .likely || mapping.confidence == .speculative {
            return MigrationClassification(category: .review, reason: "Mapping confidence is only 'likely'")
        }
        
        if !isTargetMappingKnown || dependency.targetCount != 1 {
            return MigrationClassification(category: .review, reason: "Target is ambiguous or mapping unknown")
        }
        
        let mapper = VersionMapper()
        let mappedVersion = mapper.map(constraint: dependency.versionConstraint ?? "", resolvedVersion: dependency.resolvedVersion)
        
        if mappedVersion == nil {
            return MigrationClassification(category: .review, reason: "Complex version constraint")
        }
        
        // Deterministic evidence for AUTO
        return MigrationClassification(category: .auto, reason: "Verified registry mapping and compatible version")
    }
}

private struct RegistryMappingInfo: Sendable {
    let exists: Bool
    let confidence: PkgLiftCore.MigrationConfidence
    let repositoryURL: String
    let products: [String]

    init(exists: Bool, confidence: String, repositoryURL: String = "", products: [String] = []) {
        self.exists = exists
        self.confidence = PkgLiftCore.MigrationConfidence(rawValue: confidence) ?? .speculative
        self.repositoryURL = repositoryURL
        self.products = products
    }

    init(exists: Bool, confidence: PkgLiftCore.MigrationConfidence, repositoryURL: String = "", products: [String] = []) {
        self.exists = exists
        self.confidence = confidence
        self.repositoryURL = repositoryURL
        self.products = products
    }
}

private struct DependencyInfo: Sendable {
    let isDirect: Bool
    let isExternalSource: Bool
    let hasPreInstallHooks: Bool
    let hasPostInstallHooks: Bool
    let hasDynamicLogic: Bool
    let useFrameworks: Bool
    let targetCount: Int
    let versionConstraint: String?
    let resolvedVersion: String?
    
    init(
        isDirect: Bool = true,
        isExternalSource: Bool = false,
        hasPreInstallHooks: Bool = false,
        hasPostInstallHooks: Bool = false,
        hasDynamicLogic: Bool = false,
        useFrameworks: Bool = false,
        targetCount: Int = 1,
        versionConstraint: String? = nil,
        resolvedVersion: String? = nil
    ) {
        self.isDirect = isDirect
        self.isExternalSource = isExternalSource
        self.hasPreInstallHooks = hasPreInstallHooks
        self.hasPostInstallHooks = hasPostInstallHooks
        self.hasDynamicLogic = hasDynamicLogic
        self.useFrameworks = useFrameworks
        self.targetCount = targetCount
        self.versionConstraint = versionConstraint
        self.resolvedVersion = resolvedVersion
    }
}
