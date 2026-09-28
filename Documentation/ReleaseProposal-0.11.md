# PkgLift 0.11 release proposal

Status: **source preparation approved, 2026-09-27; not published.** This
proposal covers the complete production delta from released 0.10.0 commit
`7d976d70e66a584e2e25db9852ac0e53bb6201b9` through merged main commit
`4ff7b32dce8d706153ad682aa2332d0e61993738` (PR #135). The preparation sets the
source version to `0.11.0`, adds a dated changelog entry and
[release notes](ReleaseNotes-0.11.0.md), and refreshes this evidence record.
The public release remains 0.10.0. Merge, manifest creation, signing,
notarization and publication are subsequent approval boundaries.

## Recommendation

Prepare **0.11.0** for the complete reviewed-main delta. Bounded header-import
evidence fixes a demonstrated unsafe AUTO assumption: language and registry
evidence did not show that a consumer would continue to compile after
CocoaPods header search paths were removed. The observed ZBNetworking failure
on `#import <SDImageCache.h>` is now a typed, pre-write REVIEW result.
The subsequently merged saved-plan fix also prevents the demonstrated
`.pkglift` symlink from redirecting plan output outside the selected project.

This scope includes all 22 production/package files changed from released
0.10.0 through `4ff7b32`, not only those two corrections. The preparation
additionally changes the source version and release documentation. A narrower
backport would require a separate dependency and diff review.

The selected version is a pre-1.0 minor release. The delta adds public closed
`MigrationReasonCode` cases and public report fields. Existing Swift clients
with exhaustive switches can require source changes when recompiled. It also
intentionally changes some classifications from AUTO to REVIEW. Calling that
combination `0.10.1` would obscure a material source/API and behavior change.

## Selected production scope

Release the following complete source delta, with no extra registry admission
or support expansion:

1. **Registry-source and executable-plan evidence.** Retain 0.10's exact
   executable-version, stale-entry, language/platform and target-attribution
   preflight safeguards. Extend it with statically recognized public
   CocoaPods-source declarations and `Podfile.lock` `SPEC REPOS` evidence,
   typed missing/unsupported/conflicting source refusals, conditional schema-2
   plans carrying registry-source provenance, and public-contract coverage for
   the six library products.
2. **Conservative CocoaPods and Xcode refinements.** Static Podfile/lockfile
   parsing and target-attribution refinements; retained-CocoaPods source-mode
   validation; project and workspace preservation checks; bundled-registry
   lookup in both historical command-line and macOS `Contents/Resources`
   layouts; and PBX-only project writes that preserve unrelated schemes and
   breakpoints. Input evidence that remains incomplete is refused.
3. **Partial-migration safety.** Repository-owned Swift, mixed Swift/Objective-C
   and existing-SwiftPM coexistence fixtures that retain non-AUTO CocoaPods
   entries, plus conflicting-requirement refusal. These establish bounded
   implementation coverage; they do not make arbitrary mixed-manager projects
   supported.
4. **Header-import evidence.** Bounded, read-only C-family source/header and
   configuration inspection; new `clear`, `requiresReview` and `incomplete`
   evidence states; classifier and preflight refusal where an unqualified angle
   import or unresolved quoted import may rely on CocoaPods header search paths,
   where inspection/configuration evidence is incomplete, and for legacy
   C-family AUTO plans without the new evidence. No import rewrite,
   header-search-path workaround, source generation or compiler invocation is
   added.
5. **Saved-plan write safety.** No-follow, retained directory descriptors,
   private temporary files and atomic replacement for `.pkglift/plan.json`.
   Reject symlinked state directories, unsafe destinations and observed binding
   changes. Retain the documented limit: these checks are not a filesystem
   transaction against another process able to rename open directories.
6. **Qualification and release operations.** Same-job source/consumer environment
   capture, runtime and pilot artifact identity checks, source/index preservation
   receipts, manually dispatched G2/G3 workflows, and eleven local full-baseline
   recovery drills with a runbook. These are bounded validation infrastructure
   and evidence, not completed 1.0 qualification or installed signed-CLI
   interruption acceptance.

## Public compatibility and migration notes

- New `MigrationReasonCode` cases are `registry_source_evidence_missing`,
  `registry_source_unsupported`, `registry_source_evidence_conflict`,
  `target_header_imports_require_review` and
  `target_header_import_evidence_incomplete`. Swift clients that switch
  exhaustively over that existing public enum need to handle all five cases.
- New public evidence includes `TargetHeaderImportStatus` and optional
  `TargetSourceProfile.headerImports`; `RegistrySpecRepository`,
  `RegistrySourceEvidenceStatus`, and registry-source provenance on parsed
  dependencies and plan entries. `PodfileFeatures` can report bounded
  `registrySourceDeclarations`. Generic JSON consumers must treat unknown
  fields and values conservatively.
- Plans carrying registry-source provenance use schema 2, while plans without
  it remain schema 1. The existing exact-PkgLift-version execution rule remains
  in force, so the 0.11 version change requires a fresh `analyze`/`plan` before
  dry run or apply; users must not edit producer-version or evidence fields.
- A target with an unqualified angle import, unresolved quoted header,
  unsupported configuration/input, or missing C-family header evidence can
  move from AUTO to REVIEW. This means the import may depend on CocoaPods
  header-search-path behavior; it does not say every flat import is unsafe.
  Users must not override the result by editing a plan.
- `headerImports: clear` is bounded risk evidence only. It does not establish a
  third-party package build, import compatibility, project runtime behavior or
  a new platform/language support promise.

## Explicit exclusions

- No new registry mappings, changed minimum versions, package URLs/products, or
  AUTO eligibility expansion.
- No source adaptation, header rewriting, generated configuration fabrication,
  Ruby execution, external Git migration, local-pod migration, new dependency
  manager, or automatic recovery command.
- No claim that ZBNetworking is a positive multi-target migration; its current
  valid outcome is REVIEW/refusal.
- No G2 support-matrix expansion: exact macOS 14.0 runtime and source-toolchain
  lower/upper boundary decisions remain unresolved. Same-job hosted records
  now exist for the exact PR #135 runs described below; they do not close those
  gaps. The local PartialMixed environment is recorded separately.
- No adoption of the proposed 1.0 support contract, completed 1.0 qualification,
  manifest, signed release candidate, notarization, tag, GitHub Release, or
  Homebrew publication.

## Recorded production-baseline evidence

PR #135's final reviewed head `fd202b2fccf6e15ea8e7608946ab48df299cb352`
passed 26 ordinary checks. Its [pilot/source run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36277061137)
ran against test-merge `93c2faaaabcc641c04c57c980e9865523e1e0f80`. The source job
and seven building consumer jobs supplied eight complete same-job environment
receipts: macOS 15.7.9 (24G830), arm64, Xcode 16.4 (16F6), Swift 6.1.2 and
hosted runner image `20260907.0337.1`.

The merged main commit `4ff7b32dce8d706153ad682aa2332d0e61993738` has the same
source tree as that reviewed head. Its [pilot/source](https://github.com/Alexsvensson99/PkgLift/actions/runs/36284796399),
[CodeQL](https://github.com/Alexsvensson99/PkgLift/actions/runs/36284796377) and
[Quality](https://github.com/Alexsvensson99/PkgLift/actions/runs/36284796380)
workflows passed. These are baseline checks, not verification of the subsequent
0.11.0 version-preparation commit.

The [qualification checkpoint](Qualification-2026-09-26.md) preserves historical
local and hosted identities, including the focused saved-plan correction.
The [recovery record](Recovery-1.0.md) binds eleven successful local drills to
their exact CLI/test-helper pair; it is not signed-artifact signal acceptance.
The focused security review and regression fix do not close the broader G5
safety/evidence gate.

## Required preparation and release sequence

1. Review the source-version, complete release notes and dated changelog delta.
   Run the mandatory local build, full tests and registry validation, repository
   YAML validation, release-policy regressions and documentation-link checks.
2. Pass `Mixed-Language End-to-End Pilot` (including build, tests, registry,
   artifact identity and required consumer gates), CodeQL and Quality on the
   exact preparation PR. Preserve focused reason-code, report-decoding,
   pre-write refusal and saved-plan regression coverage.
3. After separate merge approval, require successful protected main checks for
   the exact merged source-preparation commit. Earlier main checks cannot stand
   in for that commit's evidence.
4. Follow the separately approved private signed/notarized artifact acceptance
   and manifest-only publication sequence in [Distribution](Distribution.md).
   The manifest must be separate from product preparation and bind the exact
   merged preparation source and its successful main pilot run.
5. After explicit publication approval, verify the public tag/archive,
   checksum/signature/quarantine behavior and Homebrew installation/test/uninstall
   against the exact public archive.

The dated 0.11.0 changelog entry records preparation. It is not evidence of
publication. No 0.11.0 manifest or candidate artifact is part of this PR.

## Separate 1.0 scope decision

The [initial 1.0 scope proposal](ScopeProposal-1.0.md) remains unadopted.
This preparation does not defer or close the original external positive
multi-target G3 condition, redefine a refusal as positive migration evidence,
or change the public support contract. Repository-owned fixtures and the
historical AWS partial migration retain only their documented evidence scope.

G2 environment decisions, the G3 protocol or a separately adopted contract
change, broader G5 safety/evidence disposition, and G6 candidate acceptance
remain open. Preserve the completed local G4 drills and their signed-artifact
limitations. Do not restart an unbounded public-project search as part of this
0.11.0 source preparation.
