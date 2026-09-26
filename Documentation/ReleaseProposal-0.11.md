# PkgLift 0.11 release proposal

Status: **preparation only, 2026-09-26.** This proposal describes the complete
reviewed-main delta proposed for release from released 0.10.0 commit
`7d976d70e66a584e2e25db9852ac0e53bb6201b9` through reviewed main commit
`cbff61f47ebd7034509123afcc0afe0a831a009c`. It neither changes the current
`0.10.0` version nor creates a manifest, pull request, CI run, tag, signed
artifact, Homebrew update, or public release.

## Recommendation

Prepare **0.11.0**, rather than a header-only patch. The last change in the
delta, bounded header-import evidence, fixes a demonstrated unsafe AUTO
assumption: language and registry evidence did not show that a consumer would
continue to compile after CocoaPods header search paths were removed. The
observed ZBNetworking failure on `#import <SDImageCache.h>` is now a typed,
pre-write REVIEW result. That safety correction is release-worthy. This
proposal selects the complete reviewed-main delta; it does not contain the
dependency and diff review needed to say whether a narrower backport is
possible.

The version should be a pre-1.0 minor release. The delta adds public closed
`MigrationReasonCode` cases and public report fields. Existing Swift clients
with exhaustive switches can require source changes when recompiled. It also
intentionally changes some classifications from AUTO to REVIEW. Calling that
combination `0.10.1` would obscure a material source/API and behavior change.

## Proposed production scope

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
5. **Qualification and release operations.** Environment capture, runtime and
   pilot artifact identity checks, source/index preservation receipts, and
   manually dispatched G2/G3 workflows. These are validation infrastructure and
   evidence capture, not an automatic claim that all documented matrix rows or
   real-project shapes have passed.

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
- No G2 support-matrix expansion: macOS 14.0 runtime, exact source-toolchain
  lower/upper boundaries, and missing same-job hosted environment records
  remain unresolved. The local PartialMixed environment is recorded separately.
- No 1.0 qualification, release candidate, signing, notarization, distribution,
  tag, GitHub Release, or Homebrew publication.

## Remaining verification before a release decision

The current local evidence is useful preparation only. A 0.11 preparation PR
would still need the normal protected main evidence for its exact source:

1. `Mixed-Language End-to-End Pilot`, including build, full tests, registry,
   artifact identity checks and its required gates.
2. CodeQL and repository/workflow policy validation.
3. Focused regression review for the new reason codes, report decoding and
   no-write preflight behavior, including legacy C-family plans.
4. A release-manifest-only commit after the source preparation commit, followed
   by the existing signed/notarized private artifact acceptance and protected
   publication approval process.
5. After a separately approved public release, checksum/signature/quarantine
   readback and Homebrew installation/test/uninstall against the exact public
   archive.

These gates are proposed, not completed by this document. The current main
commit has no 0.11 source version, dated changelog entry, release manifest or
candidate artifact.

## Narrower 1.0 scope proposal

Keep 1.0 focused on the demonstrated fail-closed workflow instead of treating
the present G3 search as a requirement to broaden compatibility. Freeze the
candidate support wording to Apple Silicon, a specifically qualified macOS and
toolchain set, explicit selected project/workspace behavior, and only the
mapping/language/platform combinations with complete evidence. Retain the
existing non-automatic boundaries for C/C++/Objective-C++ consumers, dynamic
Podfile semantics, local/external sources and unverified project shapes.

For G3, count the repository-owned Swift, mixed-language and coexistence
fixtures, the AWS partial migration, and intentional refusal controls only for
the exact shapes they actually exercise. Do not make a successful automatic
multi-target upstream migration a 1.0 entry condition unless a separately
screened replacement candidate meets the same evidence standard. If it is not
available, state multi-target positive AUTO migration as unsupported/pending in
the 1.0 table; preserve selection/refusal coverage and never weaken it to fill
the row.

G4 recovery drills, G5 safety/evidence disposition, exact G2 environment
decisions, and G6 candidate-artifact acceptance remain release gates. This
narrowing does not alter the public 0.10 support promise; it is a proposal for
the future 1.0 contract and must be reviewed against the final evidence matrix.
