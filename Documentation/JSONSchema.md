# JSON Contracts

PkgLift's machine-readable outputs are the Swift `Codable` representations of `ProjectAnalysis`, `MigrationPlan`, and `VerificationResult`. Each top-level document includes:

- `schemaVersion` (currently `1`);
- `timestamp` in ISO-8601 format;
- `pkgLiftVersion`.

These are versioned JSON contracts, not embedded JSON Schema documents: output does not contain a `$schema` property.

## Analyze

`pkglift analyze --json` writes one `ProjectAnalysis` object to stdout. It contains `project`, `cocoaPods`, `swiftPM`, `candidates`, `issues`, `readinessScore`, and an optional `counts` object. Diagnostics and SwiftPM build warnings use stderr and do not prefix the JSON document.

The explicitly named count fields distinguish literal Podfile rows from unique direct dependencies, lockfile identities, analysis candidates, and plan entries. For schema compatibility, `cocoaPods.directDependencies` remains a source-ordered list of literal declaration rows; consumers that need unique identities should use `counts.uniqueDirectDependencyCount`. A direct dependency may also contain additive `declarations` and `targetAttribution` evidence. Each declaration records its one-based Podfile line, static scope, optional scope and target names, and source kind. Target attribution records whether all declaration destinations are `exact`, `multiple`, `partial`, or `unresolved`.

Target platform and deployment values apply project xcconfig, project settings, target xcconfig, and target settings in increasing precedence. Xcconfig resolution is confined to regular files beneath the selected project root after symlink resolution and uses bounded file-count and byte budgets. Values are emitted only when the relevant settings resolve statically and agree across every target build configuration; containment escapes, unsupported macros or conditions, unreadable include graphs, unsupported syntax, budget violations, or configuration mismatches leave both fields unset. Target, SwiftPM package, and linked-product arrays are deterministically ordered.

Each `TargetInfo` may include a `sourceProfile` with sorted `languages` values and `completeness`. The values are derived only from PBX compiled-source metadata. A candidate's `packageCandidate.supportedConsumerLanguages` records the mapping evidence. `detectedIntegrations` contains only typed enum values such as `carthage`, `reactNative`, `flutter`, and `capacitor`; it never carries integration filenames or source contents.

Each candidate continues to contain its source-ordered `reasons` string array. New output also contains optional `reasonDetails`, in the same order:

```json
{
  "code": "registry_mapping_missing",
  "message": "No registry mapping",
  "remediation": "Add an exact verified registry mapping, or keep this dependency on CocoaPods."
}
```

`code` is the stable machine-readable value, `message` is the legacy human-readable reason, and `remediation` is optional guidance. For output produced by the current classifier, `reasonDetails[*].message` exactly equals `reasons[*]`. Older schema-1 documents without `reasonDetails` remain decodable. The details are reporting metadata and are never sufficient executable migration evidence.

Current reason codes are grouped below. New codes may be added compatibly, so consumers must not treat an unknown code as permission to migrate.

| Evidence group | Stable codes |
|---|---|
| Source and mapping | `external_source_without_mapping`, `registry_mapping_missing`, `registry_identifier_mismatch`, `external_source_requires_review`, `registry_mapping_not_executable`, `registry_mapping_not_verified` |
| Dependency and declaration | `transitive_dependency`, `declaration_unrepresentable`, `declaration_provenance_missing` |
| Podfile and integration | `podfile_install_hook`, `podfile_script_phase`, `podfile_dynamic_ruby`, `podfile_use_frameworks`, `podfile_inherit_search_paths`, `podfile_abstract_target`, `carthage_integration`, `react_native_integration`, `flutter_integration`, `capacitor_integration` |
| Language and target | `consumer_language_evidence_missing`, `consumer_language_evidence_invalid`, `target_source_profile_incomplete`, `target_source_profile_empty`, `target_language_unsupported`, `target_source_profile_missing`, `target_not_found`, `target_attribution_multiple`, `target_attribution_partial`, `target_attribution_unresolved` |
| Version | `resolved_version_invalid`, `minimum_version_invalid`, `minimum_version_missing`, `version_below_minimum`, `version_requirement_unrepresentable` |
| Configuration and current project state | `configuration_denied`, `configuration_not_allowed`, `automatic_evidence_incomplete`, `existing_package_requirement_conflict` |
| Successful evidence | `verified_automatic_migration` |

The public compatibility initializer can represent an older free-form reason as `unspecified`; normal current analysis does not emit that code.

### CI failure policy

`pkglift analyze --fail-on blocked|unresolved|non-auto` evaluates only direct dependencies after the complete output has been written. `blocked` matches `BLOCKED`; `unresolved` matches `BLOCKED` and `UNKNOWN`; `non-auto` matches `REVIEW`, `BLOCKED`, and `UNKNOWN`. A match returns process status `1`. Without the flag, exit behavior is unchanged.

The policy composes with human output, `--json`, or `--portable-json`. Both JSON modes remain complete, valid documents even when the policy returns status `1`. Analysis does not create `.pkglift/plan.json` or mutate project files.

## Plan

`pkglift plan --json` writes the same `MigrationPlan` object to stdout and `.pkglift/plan.json`. Important top-level fields are `projectPath`, `entries`, `issues`, `readinessScore`, and optional `counts`.

Repeated literal declarations of the same exact pod name are represented by one deterministic entry whose `declarations` array retains every origin. An executable AUTO entry must also contain explicit `targetAttribution` with status `exact`, one target, and no unresolved declarations. Every declaration must identify that target and use the registry source. It must also contain a complete, non-empty `targetSourceProfile`; every listed language must appear in `packageCandidate.supportedConsumerLanguages`.

Plan entries use the same additive `reasonDetails` representation and preserve the same legacy `reasons` array. Preflight intentionally does not use reason text or reason details as authorization; it recomputes and compares the typed executable evidence described below.

An executable AUTO entry contains typed actions like:

```json
[
  {
    "removePod": {
      "name": "Alamofire"
    }
  },
  {
    "addSwiftPackage": {
      "repositoryURL": "https://github.com/Alamofire/Alamofire",
      "requirement": {
        "exact": {
          "_0": "5.0.0"
        }
      }
    }
  },
  {
    "linkProduct": {
      "repositoryURL": "https://github.com/Alamofire/Alamofire",
      "productName": "Alamofire",
      "targetName": "App"
    }
  }
]
```

`migrate --apply` rejects unsupported schema or PkgLift versions and rejects entries whose action list does not exactly agree with their package, version, products, pod, target, declaration, target-attribution, and consumer-language metadata.

The new evidence fields are additive, so older schema-1 JSON remains decodable for inspection. Compatibility is deliberately fail-closed: an older AUTO entry without explicit declaration provenance, exact target attribution, mapping languages, or a complete target profile is not executable and its plan must be regenerated.

## Portable analyze and plan output

`pkglift analyze --portable-json` and `pkglift plan --portable-json` are mutually exclusive with `--json`. Standard JSON encoding remains unchanged. Portable output recursively sanitizes string values and adds:

```json
{
  "portableOutput": {
    "version": 1
  }
}
```

Absolute POSIX and Windows paths, UNC paths, home paths, and explicit relative local paths are replaced without retaining the basename. `file://` locations are reduced to a redacted path marker. URL user information, passwords, queries, and fragments are removed, including from SCP-like Git syntax. Scheme-based values that cannot be parsed safely are replaced with `<redacted-url>` instead of being returned unchanged. Keys remain deterministically sorted.

`plan --portable-json` still writes the full executable `MigrationPlan` to `.pkglift/plan.json`; only stdout is portable. Portable output is intended for reproducible review, not as a privacy-minimized support report: dependency names, target names, classifications, and other project structure can remain. Use `pkglift diagnostics` when a minimized support artifact is required, and review either format before sharing it.

## Verify

`pkglift verify --json` writes one `VerificationResult` with `passed`, `checks`, and `issues`. A failed result still produces valid JSON but exits unsuccessfully, so CI can both parse the result and rely on the process status.

Any future incompatible representation requires a `schemaVersion` increment and migration/refusal behavior; existing fields must not be silently reinterpreted.
