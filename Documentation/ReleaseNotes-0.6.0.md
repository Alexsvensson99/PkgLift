# PkgLift 0.6.0

Status: **local release candidate; not released.** The latest public release
remains v0.5.0. No v0.6 publication date is assigned.

PkgLift 0.6.0 adds an evidence-backed structural blueprint for one synthetic
Swift library through the `PkgLiftCocoaPods` library API. It fills the gap
between declaration assessment and a future package generator by making the
additional caller evidence explicit. Automatic migration scope is unchanged.

## Highlights

- Assess exact, in-memory Podspec JSON bytes together with versioned evidence
  using `GeneratedPackageBlueprintAssessor.assess(podspecJSON:evidence:)`.
- Retain the original v0.5 assessment. Only its exact singleton
  `sourceSelectionRequiresGeneratedMetadata` reason at `/source_files` can be
  discharged by complete, canonical and consistent S1 evidence.
- Bind snapshot, inventory, selection, target and product assertions to their
  supplied inputs. Return `blueprintCandidate`, `insufficientEvidence`,
  `contradictoryEvidence` or `ineligibleShape`, retaining every applicable reason.
- Keep portable results deterministic and bounded, with digests and numeric
  references instead of raw names, paths or snapshot identifiers.
- Exercise every outcome and all 25 reason codes with a repository-owned
  fixture and adversarial boundary, privacy and isolation tests.

## Supported shape and safety boundary

S1 accepts one repository-owned synthetic Swift library with literal canonical
Swift source paths, one regular target and library product, one explicit
consumer context, and complete empty inventories for unsupported categories.
The reviewed provider is `pkglift.synthetic-local/v1`. A normal Podspec `source`
field, dependencies, resources, subspecs, platform scopes, other languages and
broader topology remain outside this candidate's positive shape.

Source existence, content digests, language, regular-file status, completeness
and provider claims remain caller assertions. The assessor checks their shape
and consistency in memory; it does not inspect a filesystem, execute Ruby or
CocoaPods, access the network, generate `Package.swift`, establish build/runtime
equivalence, modify a project or authorize `AUTO`.

The blueprint is a structural result, not a generated package or a package
validity certificate. Decoded result artifacts are caller data and cannot
authenticate their source. Consumers needing eligibility must reassess the
original Podspec bytes and caller-owned evidence.

## Compatibility and upgrade notes

- The new APIs are additive in `PkgLiftCocoaPods`; there is no new CLI command.
  The original v0.5 semantic model and assessment profiles remain unchanged.
- Decode untrusted bytes through `GeneratedPackageEvidence.decodeJSON(_:)` or
  `GeneratedPackageBlueprintAssessment.decodeJSON(_:)`. Direct `JSONDecoder`
  decoding is rejected, including for nested inventory and blueprint values.
- Input evidence and snapshots deliberately cannot be encoded as portable
  results. Use the result's `canonicalJSON()` for portable output.
- Regenerate migration plans after upgrading to 0.6.0. The existing preflight
  rejects a plan created by another PkgLift version, even though the serialized
  plan schema and migration eligibility rules are unchanged.

See the [evidence contract](GeneratedPackageEvidence.md),
[S1 integration record](GeneratedPackageStage1Validation.md) and
[v0.6 release gates](GeneratedPackageV06ReleaseEvidence.md) for the exact
boundaries and verification requirements. Developer ID distribution,
notarization, publication and Homebrew remain later release steps.
