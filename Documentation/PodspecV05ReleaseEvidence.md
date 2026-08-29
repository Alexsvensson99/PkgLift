# PkgLift v0.5.0 Podspec Release Evidence

Status: **release-preparation evidence for issue #71; analysis-only.** This
document describes the bounded Podspec JSON semantic model that is present in
the v0.5.0 source-preparation candidate. It is a review record, not a claim of
Podspec-to-SwiftPM migration support.

## Contract and pinned profiles

`PodspecJSONInspector` accepts caller-supplied, in-memory `Data` and produces a
typed `PodspecInspection`. `PodspecSwiftPMAssessor` then compares that completed
inspection with one explicit capability profile. Both steps are offline and
pure: they do not read a path, execute Ruby, invoke CocoaPods, start a process,
expand a glob, resolve a package, inspect a repository, contact the network, or
write project state.

| Contract input | Pinned accepted value | Refusal outside the contract |
| --- | --- | --- |
| CocoaPods semantic profile | `cocoapods-core/1.17.0` | Typed unsupported-profile error before decode/assessment |
| SwiftPM capability profile | `swift-tools-version/6.0` | Typed unsupported-profile error; no fallback to a newer surface |
| Assessment encoding | schema version `1`, canonical sorted/deduplicated reasons | Typed invalid-contract or unsupported-schema error |

The semantic-profile evidence is the CocoaPods Core 1.17.0 release and commit
documented in `Documentation/PodspecSemanticModel.md`. The exact reason-code
and profile contract is implemented by
`Sources/PkgLiftCocoaPods/PodspecSwiftPMAssessment.swift`.

## Modeled declaration categories and allowed raw scopes

`root`, `subspec`, and a scope's `platform` block mean raw declarations only;
they are never inherited, merged, or turned into an effective CocoaPods view.
The supported platform blocks are `ios`, `osx`, `tvos`, `watchos`, and
`visionos`.

| Category | Declarations | Allowed raw scopes |
| --- | --- | --- |
| Identity and topology | pod name/version, recursive `subspecs`, `platforms` | root and subspec nodes; platform declarations are held in their node's platform blocks |
| Default selection | `default_subspec`, `default_subspecs` | root global only |
| Files and headers | `source_files`, `public_header_files`, `private_header_files` | root, subspec, and their platform blocks |
| Resources | `resources`, `resource_bundles` | root, subspec, and their platform blocks |
| Dependencies | `dependencies` with literal requirement arrays | root, subspec, and their platform blocks |
| Ordinary linkage | `frameworks`, `weak_frameworks`, `libraries` | root, subspec, and their platform blocks |
| Vendored inputs | `vendored_frameworks`, `vendored_libraries` | root, subspec, and their platform blocks |
| Header layout | `header_dir`, `header_mappings_dir`, `project_header_files` | root, subspec, and their platform blocks |
| Module and linkage mode | `module_name`, `module_map`, `static_framework` | `module_name` and `static_framework`: root global only; `module_map`: root global and root platform blocks only |
| Compilation settings | `compiler_flags`, `xcconfig`, `pod_target_xcconfig`, `user_target_xcconfig` | root, subspec, and their platform blocks |
| Configuration-only dependencies | `configuration_pod_whitelist` | root and subspec global scopes only |
| Swift language declarations | `swift_versions`, legacy `swift_version` | root global only |
| ARC and file selection | `requires_arc`, `exclude_files`, `preserve_paths` | root, subspec, and their platform blocks |

Descriptive root metadata is intentionally excluded. Scripts, hooks, commands,
source provenance, test specs, and app specs are deferred evidence. Unknown or
scope-invalid keys are retained with an RFC 6901 pointer; malformed modeled
forms are typed inspection errors, not guessed semantics. In particular,
`static_library` is unknown evidence, not an alias for `static_framework`.

## Assessment outcomes

The strongest observed reason determines the outcome, without discarding
weaker reasons:

| Outcome | Meaning | Release safety boundary |
| --- | --- | --- |
| `declarationCompatible` | No modeled declaration required a downgrade under the two pinned profiles. | Not proof of package validity, file selection, build/runtime equivalence, or migration eligibility. |
| `requiresGeneratedMetadata` | A known, modeled declaration would need explicit future package metadata. | No metadata is generated in v0.5. |
| `indeterminate` | Evidence is incomplete, unknown, deferred, opaque, or requires inspection. | No inference, normalization, filesystem inspection, or fallback occurs. |
| `unsupported` | The pinned capability profile does not safely support an explicit declaration. | No flag/configuration translation or workaround is attempted. |

## Complete reason-code evidence matrix

The references name deterministic unit-test functions. The fixture references
are either pinned immutable CocoaPods Specs fixtures or repository-authored
adversarial fixtures whose provenance and SHA-256 values are recorded in
`Tests/PkgLiftCocoaPodsTests/Fixtures/PodspecJSON/README.md`.

`PodspecV05ReleaseGateTests.pinnedFixtureMatrix` assesses the three dedicated
v0.5 release fixtures and requires their exact outcomes, reason codes, evidence
paths, and SHA-256 values. `completeOutcomeAndReasonCoverage` compares the
observed union directly with every public `Code.allCases` and
`Outcome.allCases` value, including a deliberately malformed public model for
`incompleteModeledSemantic`. `deterministicCodableRoundTrip` and
`fixturePrivacyBoundary` lock the byte-stable encoding and non-disclosure
contract across the same fixture matrix.

| Reason code | Outcome | Safety boundary | Fixture / test reference |
| --- | --- | --- | --- |
| `incompleteModeledSemantic` | `indeterminate` | Invalid, contradictory, or noncanonical public model evidence is not repaired. | `PodspecSwiftPMAssessmentTests.malformedModeledEvidence`, `.contradictoryPublicModels` |
| `unknownCocoaPodsSemantic` | `indeterminate` | Unrecognized keys are retained but never interpreted. | `PodspecJSONInspectorTests.unsupportedFieldsAreFailClosedAndDeterministic`; assessor `.unsupportedReasonPrecedence` |
| `deferredCocoaPodsSemantic` | `indeterminate` | Deferred CocoaPods behavior is visible, not emulated. | `PodspecRecursiveSemanticTests.nestedUnsupportedFields`; assessor `.indeterminate` |
| `platformRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | Platform deployment metadata is not generated. | `PodspecSwiftPMAssessmentTests.requiresGeneratedMetadata` |
| `platformScopeSemanticsIndeterminate` | `indeterminate` | Platform inheritance/merge is never computed. | `PodspecRecursiveSemanticTests.recursiveHierarchyAndScopes` |
| `subspecSemanticsIndeterminate` | `indeterminate` | Subspec inheritance/effective behavior is never computed. | `PodspecRecursiveSemanticTests.recursiveHierarchyAndScopes`; assessor `.contradictoryPublicModels` |
| `defaultSubspecRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | Default-subspec selection is recorded, never emitted as package metadata. | `PodspecRecursiveSemanticTests.defaultForms`; assessor `.contradictoryPublicModels` |
| `sourceSelectionRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | Source globs are not expanded or emitted. | `PodspecJSONInspectorTests.inspectSupportedDeclarations`; assessor `.requiresGeneratedMetadata` |
| `headerSelectionRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | Header selection is not resolved or emitted. | `PodspecJSONInspectorTests.inspectSupportedDeclarations`; assessor `.monotonicDowngrades` |
| `resourceSelectionRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | Resource selection is not resolved or emitted. | `PodspecJSONInspectorTests.inspectSupportedDeclarations`; assessor `.requiresGeneratedMetadata` |
| `resourceBundleRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | Resource bundles are evidence only; no bundle target is generated. | pinned Specs fixtures in `PodspecJSONInspectorTests.pinnedCocoaPodsSpecsFixtures`; assessor `.deterministicCodableSnapshot` |
| `dependencyRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | CocoaPods requirements are not parsed, solved, or translated. | `PodspecJSONInspectorTests.inspectSupportedDeclarations`; assessor `.deterministicCodableSnapshot` |
| `linkerSettingRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | Ordinary linker declarations are not emitted. | `PodspecLinkageSemanticTests.modeledRawScopes`; assessor `.requiresGeneratedMetadata` |
| `weakFrameworkLinkageUnsupported` | `unsupported` | Weak-framework semantics have no safe v0.5 translation. | `PodspecLinkageSemanticTests.modeledRawScopes`; assessor `.monotonicDowngrades` |
| `vendoredArtifactRequiresInspection` | `indeterminate` | Paths/artifacts are not opened, globbed, or classified as binary targets. | `PodspecLinkageSemanticTests.opaqueDeclarations`; assessor `.indeterminate` |
| `moduleNameRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | Module naming is not emitted. | `PodspecLinkageSemanticTests.modeledRawScopes`; assessor `.monotonicDowngrades` |
| `generatedModuleMapRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | Generated module-map intent is not converted into package metadata. | `PodspecLinkageSemanticTests.moduleMapStates`; assessor `.monotonicDowngrades` |
| `customModuleMapRequiresInspection` | `indeterminate` | Custom module-map paths are opaque and never read. | `PodspecLinkageSemanticTests.moduleMapStates`; assessor `.monotonicDowngrades` |
| `disabledModuleMapUnsupported` | `unsupported` | Disabled module-map behavior is not translated. | `PodspecLinkageSemanticTests.moduleMapStates`; assessor `.monotonicDowngrades` |
| `headerLayoutRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | Header-layout paths are not inspected or emitted. | `PodspecLinkageSemanticTests.modeledRawScopes`; assessor `.monotonicDowngrades` |
| `linkageModeRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | `static_framework` is modeled but no linkage mode is generated. | `PodspecLinkageSemanticTests.modeledRawScopes`; assessor `.monotonicDowngrades` |
| `compilerFlagsUnsupported` | `unsupported` | Compiler flags are never copied into a generated manifest/configuration. | `PodspecCompilationSemanticTests.modeledRawScopes`; assessor `.unsupportedReasonPrecedence` |
| `buildSettingsUnsupported` | `unsupported` | xcconfig maps remain raw strings and are never merged, expanded, or written. | `PodspecCompilationSemanticTests.modeledRawScopes`; assessor `.monotonicDowngrades` |
| `configurationSpecificDependencyUnsupported` | `unsupported` | Debug/release-only dependency behavior is not generated. | `PodspecCompilationSemanticTests.modeledRawScopes`; assessor `.monotonicDowngrades` |
| `swiftVersionRequiresInspection` | `indeterminate` | Swift versions are not normalized, compared, or used as compatibility proof. | `PodspecCompilationSemanticTests.swiftVersionFormsAndUnresolvedPairs`; assessor `.contradictoryPublicModels` |
| `arcControlUnsupported` | `unsupported` | ARC booleans/patterns are not turned into compiler behavior. | `PodspecCompilationSemanticTests.modeledRawScopes`; assessor `.monotonicDowngrades` |
| `fileExclusionRequiresGeneratedMetadata` | `requiresGeneratedMetadata` | Exclusions are not expanded or emitted. | `PodspecCompilationSemanticTests.modeledRawScopes`; assessor `.requiresGeneratedMetadata` |
| `preservePathUnsupported` | `unsupported` | Preserve-path behavior is not modeled as package behavior. | `PodspecCompilationSemanticTests.modeledRawScopes`; assessor `.monotonicDowngrades` |

## Explicit unchanged production surfaces

The assessment is deliberately not consumed by `PkgLiftCLI`, `PkgLiftRegistry`,
`PkgLiftMigration`, `PkgLiftVerification`, or `PkgLiftXcode`. v0.5 changes none
of the following contracts:

- classifier result categories and their fail-closed external/path handling;
- planner actions and safe version-requirement representation;
- migration preflight evidence comparison and atomic-write sequencing;
- registry mappings, bundled-registry loading, or registry validation;
- Xcode inspection/editing or project-file mutation ownership;
- CLI command surface and serialized analysis/plan contracts; and
- `AUTO` eligibility. No Podspec assessment outcome, including
  `declarationCompatible`, can authorize `AUTO` or `migrate --apply`.

`Tests/PkgLiftMigrationTests/PodspecAssessmentIsolationTests` is the release
regression guard: it proves an intentionally unsupported assessment can coexist
with the pre-existing verified `Alamofire` planner contract, and scans
production migration surfaces to ensure assessment symbols do not cross the
analysis-only boundary.

## Gates and evidence ownership

### Local source-preparation gates

Run these against the final source-preparation commit:

```bash
swift build -j 2
swift build -c release -j 2
swift test -j 2
swift run -j 2 pkglift registry validate
ruby Scripts/validate-repository-yaml.rb
git diff --check
swift build -c release -j 2 --arch arm64
bash Scripts/package-release.sh release /tmp/pkglift-release
```

If `site/` changes, also run:

```bash
python3 Scripts/validate-pages-site.py --site site
```

These checks can establish local source, unit, registry, static-site, archive,
checksum, arm64/macOS-14, adjacent-registry-bundle, symlink, and missing-bundle
typed-error evidence. They cannot establish signing, notarization, an Actions
run, a protected-environment approval, a tag, a GitHub Release, or Homebrew
distribution.

### GitHub and publication gates

After source preparation is merged, GitHub must independently pass the Build,
Test, Quality, Registry Validation, CodeQL, Pinned Pilots, and Mixed-Language
End-to-End Pilot workflows applicable to the commit. The positive E2E and pinned
pilot evidence remains regression coverage for existing migration behavior; it
does not claim that v0.5 performs Podspec migration.

Only then may a reviewed, separate one-file
`.github/releases/v0.5.0.json` manifest identify the full merged source
preparation SHA. The manifest workflow verifies the version/date/head/ancestry
contract, dispatches signing/notarization, verifies the private artifact, and
waits at the protected production-release environment before tag/release
creation. A public release and Homebrew formula update require their separate
approvals and the verified public archive SHA.
