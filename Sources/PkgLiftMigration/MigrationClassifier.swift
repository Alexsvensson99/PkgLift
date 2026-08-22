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
    public let reasonDetails: [MigrationReason]
    
    public init(category: MigrationCategory, reason: String) {
        self.category = category
        self.reason = reason
        self.reasons = [reason]
        self.reasonDetails = [MigrationReason(code: .unspecified, message: reason)]
    }

    public init(category: MigrationCategory, reasons: [String]) {
        let stableReasons = deduplicated(reasons)
        self.category = category
        self.reason = stableReasons.first ?? "No classification reason available"
        self.reasons = stableReasons
        self.reasonDetails = stableReasons.map {
            MigrationReason(code: .unspecified, message: $0)
        }
    }

    public init(category: MigrationCategory, reasonDetails: [MigrationReason]) {
        let stableReasons = deduplicated(reasonDetails)
        self.category = category
        self.reasonDetails = stableReasons
        self.reasons = stableReasons.map(\.message)
        self.reason = self.reasons.first ?? "No classification reason available"
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
        targetSourceProfile: TargetSourceProfile? = nil,
        projectIntegrations: [ProjectIntegration] = [],
        podfileFeatures: PodfileFeatures = PodfileFeatures()
    ) -> MigrationClassification {
        let externalGitEvidenceStatus: GitSourceEvidenceStatus? = {
            if case let .git(provenance)? = dependency.sourceProvenance {
                return provenance.status
            }
            if case .git = dependency.source {
                // Compatibility artifacts can carry a legacy Git source but no
                // typed provenance. Missing evidence must remain fail-closed.
                return .incomplete
            }
            return nil
        }()
        let dependencyInfo = DependencyInfo(
            identifier: dependency.name,
            isDirect: dependency.isDirect,
            isExternalSource: {
                if externalGitEvidenceStatus != nil {
                    return true
                }
                switch dependency.source {
                case .git, .path:
                    return true
                case .registry, .unknown:
                    return false
                }
            }(),
            hasUnrepresentableDeclaration: dependency.source == .unknown,
            hasLiteralDeclarationProvenance: dependency.hasLiteralMigrationProvenance,
            externalGitEvidenceStatus: externalGitEvidenceStatus,
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
                minimumVersion: $0.swiftpm.minimumVersion,
                supportedConsumerLanguages: $0.swiftpm.supportedConsumerLanguages
            )
        }
        
        return classify(
            dependency: dependencyInfo,
            mapping: mappingInfo,
            isAlreadyMigrated: isAlreadyMigrated,
            isTargetMappingKnown: isTargetMappingKnown,
            targetSourceProfile: targetSourceProfile,
            projectIntegrations: Array(Set(
                projectIntegrations + podfileFeatures.integrationMarkers
            )).sorted()
        )
    }

    private func classify(
        dependency: DependencyInfo,
        mapping: RegistryMappingInfo?,
        isAlreadyMigrated: Bool = false,
        isTargetMappingKnown: Bool = true,
        targetSourceProfile: TargetSourceProfile? = nil,
        projectIntegrations: [ProjectIntegration] = []
    ) -> MigrationClassification {
        var reasons: [MigrationReason] = []

        if mapping == nil {
            if dependency.isExternalSource {
                reasons.append(MigrationReason(
                    code: .externalSourceWithoutMapping,
                    message: "External source without mapping",
                    remediation: "Keep the dependency on CocoaPods or add and verify an exact registry mapping."
                ))
                reasons.append(MigrationReason(
                    code: .registryMappingMissing,
                    message: "No registry mapping",
                    remediation: "Add an exact verified registry mapping, or keep this dependency on CocoaPods."
                ))
            } else {
                reasons.append(MigrationReason(
                    code: .registryMappingMissing,
                    message: "No registry mapping",
                    remediation: "Add an exact verified registry mapping, or keep this dependency on CocoaPods."
                ))
            }
        } else if mapping?.identifier != dependency.identifier {
            reasons.append(MigrationReason(
                code: .registryIdentifierMismatch,
                message: "Registry mapping identifier does not exactly match dependency",
                remediation: "Use an exact registry identity for this CocoaPod declaration."
            ))
        }

        if !dependency.isDirect {
            reasons.append(MigrationReason(
                code: .transitiveDependency,
                message: "Transitive dependency is not a removable Podfile declaration",
                remediation: "Migrate only its owning direct CocoaPod declaration."
            ))
        }

        if dependency.hasUnrepresentableDeclaration {
            reasons.append(MigrationReason(
                code: .declarationUnrepresentable,
                message: "Podfile declaration source, options, or expressions cannot be represented safely",
                remediation: "Rewrite the declaration as a supported unconditional literal before regenerating the plan."
            ))
        }

        if let externalGitEvidenceStatus = dependency.externalGitEvidenceStatus {
            reasons.append(externalGitEvidenceStatus.migrationReason)
        }

        if mapping != nil, dependency.isDirect, !dependency.hasLiteralDeclarationProvenance {
            reasons.append(MigrationReason(
                code: .declarationProvenanceMissing,
                message: "Literal Podfile declaration provenance is missing or inconsistent",
                remediation: "Regenerate analysis from an unchanged Podfile containing a supported literal declaration."
            ))
        }

        if dependency.isExternalSource, mapping != nil {
            reasons.append(MigrationReason(
                code: .externalSourceRequiresReview,
                message: "External dependency source requires manual review",
                remediation: "Keep the dependency on CocoaPods or review an explicit external-source migration manually."
            ))
        }

        if let mapping,
           mapping.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || mapping.products.isEmpty
            || !mapping.products.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            reasons.append(MigrationReason(
                code: .registryMappingNotExecutable,
                message: "Registry mapping lacks an executable package URL or product",
                remediation: "Correct and revalidate the registry mapping before automatic migration."
            ))
        }

        if dependency.hasPreInstallHooks || dependency.hasPostInstallHooks {
            reasons.append(MigrationReason(
                code: .podfileInstallHook,
                message: "Podfile install hook detected",
                remediation: "Review this project-level CocoaPods behavior manually; PkgLift does not convert it automatically."
            ))
        }
        if dependency.hasScriptPhase {
            reasons.append(MigrationReason(
                code: .podfileScriptPhase,
                message: "Podfile script_phase detected",
                remediation: "Review this project-level CocoaPods behavior manually; PkgLift does not convert it automatically."
            ))
        }
        if dependency.hasDynamicLogic {
            reasons.append(MigrationReason(
                code: .podfileDynamicRuby,
                message: "Dynamic Podfile logic detected",
                remediation: "Replace dynamic dependency logic with supported static literals before regenerating the plan."
            ))
        }
        if dependency.useFrameworks {
            reasons.append(MigrationReason(
                code: .podfileUseFrameworks,
                message: "use_frameworks! detected",
                remediation: "Review framework-linkage behavior manually before migration."
            ))
        }
        if dependency.hasInheritSearchPaths {
            reasons.append(MigrationReason(
                code: .podfileInheritSearchPaths,
                message: "inherit! :search_paths detected",
                remediation: "Review inherited target behavior manually before migration."
            ))
        }
        if dependency.hasAbstractTargets {
            reasons.append(MigrationReason(
                code: .podfileAbstractTarget,
                message: "abstract_target detected",
                remediation: "Review abstract-target inheritance manually before migration."
            ))
        }
        reasons.append(contentsOf: projectIntegrations.sorted().map { integration in
            MigrationReason(
                code: integration.reasonCode,
                message: integration.reviewReason,
                remediation: "Keep this integration unchanged and review the dependency migration manually."
            )
        })

        if let mapping, mapping.confidence != .verified {
            reasons.append(MigrationReason(
                code: .registryMappingNotVerified,
                message: "Registry mapping is not verified",
                remediation: "Verify the registry mapping against upstream package metadata before automatic migration."
            ))
        }

        if let mapping {
            let supportedLanguages = mapping.supportedConsumerLanguages
            if supportedLanguages?.isEmpty != false {
                reasons.append(MigrationReason(
                    code: .consumerLanguageEvidenceMissing,
                    message: "Registry mapping has no verified consumer-language support",
                    remediation: "Add verified consumer-language evidence or keep the dependency on CocoaPods."
                ))
            } else if let supportedLanguages,
                      Set(supportedLanguages).count != supportedLanguages.count {
                reasons.append(MigrationReason(
                    code: .consumerLanguageEvidenceInvalid,
                    message: "Registry mapping consumer-language evidence is invalid",
                    remediation: "Remove duplicate or unknown language evidence and revalidate the mapping."
                ))
            }

            if let targetSourceProfile {
                if targetSourceProfile.completeness != .complete {
                    reasons.append(MigrationReason(
                        code: .targetSourceProfileIncomplete,
                        message: "Target source-language profile is incomplete",
                        remediation: "Resolve unknown or missing compiled source metadata before regenerating the plan."
                    ))
                }
                if targetSourceProfile.languages.isEmpty {
                    reasons.append(MigrationReason(
                        code: .targetSourceProfileEmpty,
                        message: "Target source-language profile contains no compiled source languages",
                        remediation: "Confirm the target's compiled source membership before migration."
                    ))
                }
                if let supportedLanguages {
                    let supported = Set(supportedLanguages)
                    let unsupported = targetSourceProfile.languages.filter { !supported.contains($0) }
                    if !unsupported.isEmpty {
                        reasons.append(MigrationReason(
                            code: .targetLanguageUnsupported,
                            message: "Target source languages are not supported by the registry mapping: "
                                + unsupported.map(\.rawValue).joined(separator: ", "),
                            remediation: "Use a mapping that explicitly supports every compiled target language."
                        ))
                    }
                }
            } else {
                reasons.append(MigrationReason(
                    code: .targetSourceProfileMissing,
                    message: "Target source-language profile is missing",
                    remediation: "Analyze an exact Xcode target with complete compiled source metadata."
                ))
            }
        }

        switch dependency.targetAttributionStatus {
        case .exact:
            if !isTargetMappingKnown || dependency.targetCount != 1 {
                reasons.append(MigrationReason(
                    code: .targetNotFound,
                    message: "Podfile target does not match exactly one existing Xcode target",
                    remediation: "Use a statically provable literal target that matches exactly one Xcode target."
                ))
            }
        case .multiple:
            reasons.append(MigrationReason(
                code: .targetAttributionMultiple,
                message: dependency.targetAttributionReason ?? "Multiple Podfile targets are proven",
                remediation: "Split or review the declaration because it applies to multiple targets."
            ))
        case .partial:
            reasons.append(MigrationReason(
                code: .targetAttributionPartial,
                message: dependency.targetAttributionReason ?? "Target attribution is partial",
                remediation: "Make all target inheritance and helper calls statically provable before migration."
            ))
        case .unresolved:
            reasons.append(MigrationReason(
                code: .targetAttributionUnresolved,
                message: dependency.targetAttributionReason ?? "Target is unresolved from static Podfile structure",
                remediation: "Use a statically provable literal target before regenerating the plan."
            ))
        }

        let resolvedVersion: SemanticVersion?
        if let resolvedVersionText = dependency.resolvedVersion,
           let parsed = SemanticVersion(rawValue: resolvedVersionText) {
            resolvedVersion = parsed
        } else {
            resolvedVersion = nil
            reasons.append(MigrationReason(
                code: .resolvedVersionInvalid,
                message: "Resolved version is missing or is not stable major.minor.patch",
                remediation: "Provide a stable locked major.minor.patch version before migration."
            ))
        }

        var minimumVersion: SemanticVersion?
        if let mapping {
            if let minimumVersionText = mapping.minimumVersion {
                if let parsed = SemanticVersion(rawValue: minimumVersionText) {
                    minimumVersion = parsed
                } else {
                    minimumVersion = nil
                    reasons.append(MigrationReason(
                        code: .minimumVersionInvalid,
                        message: "Registry mapping minimum SwiftPM version is invalid",
                        remediation: "Correct and revalidate the mapping's minimum SwiftPM version."
                    ))
                }
            } else {
                minimumVersion = nil
                reasons.append(MigrationReason(
                    code: .minimumVersionMissing,
                    message: "Registry mapping has no verified minimum SwiftPM version",
                    remediation: "Verify and record the first supported SwiftPM version in the registry."
                ))
            }
        }

        if let resolvedVersion, let minimumVersion, resolvedVersion < minimumVersion {
            reasons.append(MigrationReason(
                code: .versionBelowMinimum,
                message: "Resolved version \(resolvedVersion) predates verified SwiftPM support at \(minimumVersion)",
                remediation: "Upgrade the CocoaPod to at least \(minimumVersion) or review the migration manually."
            ))
        }

        if resolvedVersion != nil,
           VersionMapper().map(
                constraint: dependency.versionConstraint ?? "",
                resolvedVersion: dependency.resolvedVersion
           ) == nil {
            reasons.append(MigrationReason(
                code: .versionRequirementUnrepresentable,
                message: "Version requirement cannot be represented safely",
                remediation: "Use a supported literal CocoaPods version requirement and regenerate the plan."
            ))
        }

        let stableReasons = deduplicated(reasons)
        if stableReasons.isEmpty,
           let resolvedVersion,
           let minimumVersion {
            return MigrationClassification(
                category: .auto,
                reasonDetails: [
                    MigrationReason(
                        code: .verifiedAutomaticMigration,
                        message: "Verified exact registry mapping and target language support; resolved version \(resolvedVersion) meets minimum \(minimumVersion)"
                    ),
                ]
            )
        }

        let category: MigrationCategory
        if mapping == nil {
            category = dependency.isExternalSource ? .blocked : .unknown
        } else {
            category = .review
        }
        return MigrationClassification(category: category, reasonDetails: stableReasons)
    }
}

private func deduplicated(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
}

private func deduplicated(_ values: [MigrationReason]) -> [MigrationReason] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0.message).inserted }
}

private extension ProjectIntegration {
    var reasonCode: MigrationReasonCode {
        switch self {
        case .carthage:
            return .carthageIntegration
        case .reactNative:
            return .reactNativeIntegration
        case .flutter:
            return .flutterIntegration
        case .capacitor:
            return .capacitorIntegration
        }
    }
}

private extension GitSourceEvidenceStatus {
    var migrationReason: MigrationReason {
        switch self {
        case .supportedImmutable:
            return MigrationReason(
                code: .externalGitSourceAnalyzed,
                message: "External Git source has supported immutable provenance",
                remediation: "Review the external source manually; analyzed provenance does not authorize automatic migration."
            )
        case .mutable:
            return MigrationReason(
                code: .externalGitMutableReference,
                message: "External Git source uses a mutable branch reference",
                remediation: "Keep the dependency on CocoaPods or replace the branch with reviewed immutable evidence."
            )
        case .unpinned:
            return MigrationReason(
                code: .externalGitUnpinned,
                message: "External Git source is not pinned to a reference",
                remediation: "Pin and review the external source before considering a manual migration."
            )
        case .credentialBearing:
            return MigrationReason(
                code: .externalGitCredentialsRedacted,
                message: "External Git credentials were detected and redacted",
                remediation: "Remove credentials from source declarations and use an approved credential mechanism."
            )
        case .incomplete:
            return MigrationReason(
                code: .externalGitEvidenceIncomplete,
                message: "External Git source evidence is incomplete",
                remediation: "Regenerate analysis with matching static Podfile and lockfile evidence."
            )
        case .conflicting:
            return MigrationReason(
                code: .externalGitEvidenceConflict,
                message: "External Git source evidence conflicts",
                remediation: "Resolve declaration and lockfile source differences before reviewing migration."
            )
        case .ambiguousRepository:
            return MigrationReason(
                code: .externalGitRepositoryAmbiguous,
                message: "External Git repository identity is ambiguous",
                remediation: "Use a complete, statically recognizable repository identity."
            )
        case .unsupportedURL:
            return MigrationReason(
                code: .externalGitURLUnsupported,
                message: "External Git repository URL is unsupported",
                remediation: "Use a supported HTTPS, SSH, or SCP-style repository URL."
            )
        case .unsupportedSyntax:
            return MigrationReason(
                code: .externalGitSyntaxUnsupported,
                message: "External Git declaration syntax is unsupported",
                remediation: "Rewrite the declaration using one literal Git URL and at most one supported reference."
            )
        }
    }
}

private struct RegistryMappingInfo: Sendable {
    let identifier: String
    let confidence: PkgLiftCore.MigrationConfidence
    let repositoryURL: String
    let products: [String]
    let minimumVersion: String?
    let supportedConsumerLanguages: [SourceLanguage]?
}

private struct DependencyInfo: Sendable {
    let identifier: String
    let isDirect: Bool
    let isExternalSource: Bool
    let hasUnrepresentableDeclaration: Bool
    let hasLiteralDeclarationProvenance: Bool
    let externalGitEvidenceStatus: GitSourceEvidenceStatus?
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
        externalGitEvidenceStatus: GitSourceEvidenceStatus? = nil,
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
        self.externalGitEvidenceStatus = externalGitEvidenceStatus
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
