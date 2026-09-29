# PkgLift 0.11.0 — Migration evidence and saved-plan safety

Status: **source preparation, 2026-09-27; not published.** The public download
and Homebrew release remain 0.10.0. This preparation covers the complete
production delta from released 0.10.0 (`7d976d70e66a584e2e25db9852ac0e53bb6201b9`)
through merged main `4ff7b32dce8d706153ad682aa2332d0e61993738`, plus the 0.11.0
version and release documentation. It adds no registry mappings or platform
support promises.

## Safer automatic migration decisions

PkgLift now inspects bounded C-family source/header and configuration evidence
before classifying or applying an automatic migration. An unqualified angle
import such as `#import <SDImageCache.h>`, an unresolved quoted import, or
incomplete evidence can move a dependency from AUTO to REVIEW. The observed
ZBNetworking case built under CocoaPods but failed after migration; it now
refuses the affected migration before writing project files.

The `clear` result records a bounded risk check. It does not prove a package
build or runtime behavior. PkgLift does not rewrite imports or manufacture
header-search-path configuration to make a project pass.

Registry-source evidence reconciles supported literal public CocoaPods source
declarations and lockfile `SPEC REPOS`. Missing, unsupported and conflicting
evidence produces typed refusals, including during executable-plan preflight.
This does not add migration of private, local or external Git dependencies.

Static Podfile parsing, target attribution and retained-CocoaPods source-mode
validation are stricter. Existing SwiftPM requirements are checked for hidden
conflicts. Repository-owned Swift, mixed-language and coexistence fixtures
exercise partial migrations that preserve the remaining CocoaPods entries;
they do not establish support for arbitrary mixed-manager projects.

## Saved plans and project preservation

Saved `.pkglift/plan.json` writes now use retained, no-follow directory
descriptors, private staging files, binding checks and atomic replacement.
A symlinked `.pkglift` directory or non-regular plan destination is refused,
preventing the demonstrated redirected write outside the selected project.
Observed binding changes are refused. This is not a filesystem transaction
against another process able to rename open directories, nor a power-loss
recovery guarantee.

Xcode edits write the PBX file while preserving unrelated schemes and
breakpoints. Bundled-registry lookup supports both the historical command-line
layout and macOS `Contents/Resources` layout.

## Upgrade compatibility

Regenerate saved plans with 0.11.0 before dry run or apply:

```bash
pkglift analyze
pkglift plan
pkglift migrate
```

Review the new plan before separately choosing `migrate --apply`. The existing
exact-producer-version check rejects older plans; do not edit their version or
evidence fields to bypass it. Plans carrying registry-source provenance use
schema 2; plans without it retain schema 1.

Five cases were added to the public `MigrationReasonCode` enum:

- `registry_source_evidence_missing`
- `registry_source_unsupported`
- `registry_source_evidence_conflict`
- `target_header_imports_require_review`
- `target_header_import_evidence_incomplete`

Swift clients with exhaustive switches need to handle these cases. Public
report additions include `TargetHeaderImportStatus`, optional
`TargetSourceProfile.headerImports`, `RegistrySpecRepository`,
`RegistrySourceEvidenceStatus`, registry-source provenance and bounded
`PodfileFeatures.registrySourceDeclarations`. JSON consumers should handle new
fields and enum values conservatively. These source/API and classification
changes are why this preparation uses the pre-1.0 minor version 0.11.0.

## Evidence and remaining release work

The production baseline's [main pilot/source run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36284796399),
[CodeQL run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36284796377)
and [Quality run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36284796380)
passed. They cover `4ff7b32`, not the subsequent version-preparation commit.
The preparation PR requires its own ordinary protected checks.

Eleven [local recovery drills](Recovery-1.0.md) passed against their recorded
source and CLI/test-helper identities. They exercised handled/unhandled
interruptions and post-apply install/build failures, followed by full-baseline
restoration, builds and fresh plans. They do not qualify signals delivered to
an installed signed release CLI. Same-job environment receipts and focused
saved-plan regressions add bounded evidence; no full-repository security audit
or completed 1.0 qualification is claimed.

Exact macOS 14.0 runtime evidence, final source-toolchain boundaries and an
external positive multi-target migration remain open in the 1.0 qualification
record. The [1.0 scope proposal](ScopeProposal-1.0.md) has not been adopted by
this preparation. Existing distribution requirements remain in force.

After source preparation is reviewed, merged and passes its exact main checks,
the separate manifest and private signed/notarized artifact acceptance steps
must follow the [distribution contract](Distribution.md). Public tag, GitHub
Release and Homebrew publication require their own approval. No 0.11.0
manifest, signed candidate or public artifact is supplied by this preparation.
