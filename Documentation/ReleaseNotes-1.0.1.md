# PkgLift 1.0.1 — Project-format safety and dependency maintenance

Status: **source preparation only; not published.** Prepared on 2026-09-30.
The published version remains 1.0.0. No 1.0.1 release manifest, signed archive,
release tag or Homebrew update is part of this source preparation.

## Changes

- Refuse unsupported `.xcproj` entries before analysis or migration, including
  bundles containing both PBX and JSON definitions. The editor rechecks before
  writing, and direct migration-library callers are checked before changing
  Podfile or creating recovery state. Recovery-marker priority is preserved.
- Update XcodeProj to 9.17.5 and retain the format boundary when the dependency
  can read additional formats. This does not add JSON-project migration support.
- Update the SHA-pinned CodeQL init/analyze actions to 4.38.2, preserving their
  triggers, permissions, analysis settings and required gate.
- Include the first-pilot guide and migration-report improvements introduced
  after 1.0.0. The guide ends at a reviewed dry run.

The maintenance changes are tracked in [#141](https://github.com/Alexsvensson99/PkgLift/pull/141),
[#133](https://github.com/Alexsvensson99/PkgLift/pull/133) and
[#134](https://github.com/Alexsvensson99/PkgLift/pull/134).

## Compatibility and upgrade

The intended CLI, JSON and six-library API contracts and positive support
boundaries are unchanged. External positive multi-target/workspace migration
remains deferred. No classification or migration safety check is weakened.

Regenerate analysis and executable plans with 1.0.1 before dry run or apply,
including plans created by 1.0.0. Do not edit producer-version or evidence fields
to reuse an older plan. Publication and exact-candidate qualification are still
required before these preparation sources become a supported release.

## Remaining release qualification

1. Complete the final source candidate's required build, test, registry, unsigned
   packaging, CodeQL and Quality checks. Review and merge the source preparation,
   then bind a successful required main-branch pilot run to its exact final source
   commit F. Retain the six-module API comparison and actual local/hosted
   environment receipts.
2. Run the bounded external AWS migration and conservative-refusal protocol on
   the new candidate. The changed XcodeProj dependency prevents treating 1.0.0's
   unchanged-input receipts as qualification of this candidate.
3. Prepare a manifest-only child M of F for `v1.0.1`, binding F, its preparation
   PR and successful pilot run. Complete the release workflow's new signing,
   notarization, quarantine, runtime, full/partial migration and refusal checks,
   including the separate macOS 14 runtime job.
4. Before production approval, qualify the same signed M archive locally with
   Xcode 27: core runtime, PartialSwift, PartialMixed, PartialSwiftCoexistence and
   the full mixed-language migration/build. Record observed environments and
   exact archive/binary/registry hashes; keep the reviewed consumer build settings.
5. After release approval, verify the public tag and downloaded assets, then
   prepare and validate the Homebrew update and the applicable documentation
   distribution. Until then, do not claim 1.0.1 is signed, notarized or released.

The [1.0 release record](ReleaseNotes-1.0.0.md),
[compatibility policy](API-1.0.md) and
[distribution procedure](Distribution.md) provide the baseline process;
their old binary acceptance results are not acceptance of a new 1.0.1 binary.
