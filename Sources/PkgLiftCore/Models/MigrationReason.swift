// PkgLiftCore/Models/MigrationReason.swift
// Stable, actionable migration classification evidence.

import Foundation

/// Stable machine-readable codes for migration classification evidence.
///
/// Codes are additive reporting metadata. Executable migration safety remains
/// defined by the typed package, declaration, target, language, version, and
/// action evidence validated by migration preflight.
public enum MigrationReasonCode: String, Sendable, Codable, CaseIterable {
    case externalSourceWithoutMapping = "external_source_without_mapping"
    case registryMappingMissing = "registry_mapping_missing"
    case registryIdentifierMismatch = "registry_identifier_mismatch"
    case transitiveDependency = "transitive_dependency"
    case declarationUnrepresentable = "declaration_unrepresentable"
    case declarationProvenanceMissing = "declaration_provenance_missing"
    case externalSourceRequiresReview = "external_source_requires_review"
    case registryMappingNotExecutable = "registry_mapping_not_executable"
    case podfileInstallHook = "podfile_install_hook"
    case podfileScriptPhase = "podfile_script_phase"
    case podfileDynamicRuby = "podfile_dynamic_ruby"
    case podfileUseFrameworks = "podfile_use_frameworks"
    case podfileInheritSearchPaths = "podfile_inherit_search_paths"
    case podfileAbstractTarget = "podfile_abstract_target"
    case carthageIntegration = "carthage_integration"
    case reactNativeIntegration = "react_native_integration"
    case flutterIntegration = "flutter_integration"
    case capacitorIntegration = "capacitor_integration"
    case registryMappingNotVerified = "registry_mapping_not_verified"
    case consumerLanguageEvidenceMissing = "consumer_language_evidence_missing"
    case consumerLanguageEvidenceInvalid = "consumer_language_evidence_invalid"
    case targetSourceProfileIncomplete = "target_source_profile_incomplete"
    case targetSourceProfileEmpty = "target_source_profile_empty"
    case targetLanguageUnsupported = "target_language_unsupported"
    case targetSourceProfileMissing = "target_source_profile_missing"
    case targetNotFound = "target_not_found"
    case targetAttributionMultiple = "target_attribution_multiple"
    case targetAttributionPartial = "target_attribution_partial"
    case targetAttributionUnresolved = "target_attribution_unresolved"
    case resolvedVersionInvalid = "resolved_version_invalid"
    case minimumVersionInvalid = "minimum_version_invalid"
    case minimumVersionMissing = "minimum_version_missing"
    case versionBelowMinimum = "version_below_minimum"
    case versionRequirementUnrepresentable = "version_requirement_unrepresentable"
    case configurationDenied = "configuration_denied"
    case configurationNotAllowed = "configuration_not_allowed"
    case automaticEvidenceIncomplete = "automatic_evidence_incomplete"
    case existingPackageRequirementConflict = "existing_package_requirement_conflict"
    case verifiedAutomaticMigration = "verified_automatic_migration"

    /// Compatibility code for callers using the legacy free-form initializer.
    /// PkgLift's own classifier never emits this code.
    case unspecified = "unspecified"
}

/// One stable classification reason and its human guidance.
public struct MigrationReason: Sendable, Codable, Equatable {
    public let code: MigrationReasonCode
    public let message: String
    public let remediation: String?

    public init(
        code: MigrationReasonCode,
        message: String,
        remediation: String? = nil
    ) {
        self.code = code
        self.message = message
        self.remediation = remediation
    }
}
