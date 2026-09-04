# PkgLift v0.6.0 Release Evidence and Gates

Status: **local release preparation; not a published release.** This document
defines the candidate's source and packaging gates and records the already
completed S1 integration evidence. It does not assert that the final
preparation commit has passed GitHub CI or distribution checks.

## Candidate contract

The release target is `0.6.0`, with the implementation integrated in
[`208ee39`](https://github.com/Alexsvensson99/PkgLift/commit/208ee391bd15c72289641718e60a70f62d2a1af4)
through [PR #84](https://github.com/Alexsvensson99/PkgLift/pull/84).
The [Stage 1 record](GeneratedPackageStage1Validation.md) binds its successful
seven main workflows and 21 commit checks to that exact implementation commit.
The version/documentation preparation is a later source change and needs its
own local validation and CI evidence before distribution.

The candidate implements only the synthetic, read-only S1 contract in
[GeneratedPackageEvidence.md](GeneratedPackageEvidence.md). The new API is
confined to `PkgLiftCocoaPods`; it does not generate a manifest, verify supplied
file contents, widen supported Podspec shapes or change automatic migration.
`Version.swift` identifies the candidate as `0.6.0`. Keeping the changelog under
`Unreleased` and the [release notes](ReleaseNotes-0.6.0.md) marked as a candidate
means this preparation is deliberately not ready for a publication manifest.

## Source evidence

The 16 tests in
`Tests/PkgLiftCocoaPodsTests/GeneratedPackageBlueprintTests.swift` exercise:

| Contract | Representative tests |
| --- | --- |
| Exact S1 positive gate and preserved v0.5 assessment | `s1FixtureCandidateAndRoundTrip`, `singletonSelectionAndRawPodspecPathBoundary` |
| All four outcomes and all 25 reason codes | `resultOutcomes`, `everyReasonCode` |
| Canonical paths, complete inventories and bounded topology | `inventoryContractFailures`, `consumerAndTargetShapeBoundaries`, `declarationBoundaries` |
| Exact input bytes and caller assessment bindings | `fixtureByteDigests`, `byteExactPodspecBinding`, `callerAssessmentBinding` |
| Unknown, missing, duplicate and noncanonical JSON | `evidenceDecodingBoundary`, `resultDecodingBoundaryAndPrivacy`, `negativeResultReasonDecodingBoundaries` |
| Direct-decoder rejection, source limits and output budget | `directDecoderBoundaryAndMaximumInventory`, `resultDiagnosticBudget` |
| Separation from migration and CLI consumers | `sourceIsolationRegression`, existing `PodspecAssessmentIsolationTests` |

The positive fixture is repository-owned synthetic evidence. Its documented
file hashes do not make the assessor a filesystem evidence provider. Existing
v0.5 fixtures and regression tests remain part of the full suite.

## Local candidate acceptance

Run the following against the final candidate source and record the exact Git
commit, compiler version, commands, results and artifact SHA-256 separately:

```bash
swift build -j 2
swift test -j 2
swift build -c release -j 2 --arch arm64
swift run --skip-build pkglift registry validate
ruby Scripts/validate-repository-yaml.rb
python3 -m unittest discover -s Tests/ReleaseManifestTests -p 'test_*.py'
git diff --check 208ee391bd15c72289641718e60a70f62d2a1af4 HEAD
bash Scripts/package-release.sh release /path/to/a-new-local-rc-directory
```

Use a new, empty output directory for every packaging attempt. Where the local
sandbox requires it, use task-local SwiftPM/compiler cache paths and
`--disable-sandbox`; this does not change the product's safety rules.

Acceptance requires both CLI version forms (`version` and `--version`) to
report `0.6.0` from the extracted archive. Verify the packaged binary's bytes,
checksum, arm64 architecture, macOS 14 minimum, adjacent registry bundle,
installed-style symlink lookup and typed missing-bundle refusal. The existing
packaging script covers these packaging checks except version and Git identity,
which must be recorded explicitly.

The package script also creates a `*-notarization.zip` input file. Its filename
does not imply a notarization submission or acceptance. Local linker/ad hoc
signing, if present, is not Developer ID distribution signing. These local
checks cannot establish public distribution or reproducible archive bytes
across independent builds.

Store the candidate's local report and raw logs in the ignored
`.pkglift/validation/` directory of its working copy. Record a clean Git status
and the complete diff from the preparation base to candidate HEAD. Identify
evidence from the earlier implementation commit separately from candidate checks.

## Final preparation and publication gates

1. Review the final release scope and date. Move the 0.6.0 changes from
   `Unreleased` into a dated `## [0.6.0] - YYYY-MM-DD` section and finalize the
   release notes without claiming publication before it occurs.
2. Merge the reviewed product-preparation PR and require all seven workflows
   on its exact final `main` commit. PR #84 and its pilot run cannot substitute
   for the later preparation PR and commit.
3. Only then prepare the separately reviewed, one-file
   `.github/releases/v0.6.0.json` change. Its source SHA, preparation PR and
   positive E2E run must identify that final preparation commit. The manifest
   commit must be the single direct child of it, as required by the
   [distribution workflow](Distribution.md).
4. Complete Developer ID signing, notarization and extracted-artifact checks
   through the protected distribution workflow. Public tag/release creation
   and Homebrew publication remain separately approved steps.

No new release manifest, signing/notarization request, workflow dispatch,
tag, GitHub Release or Homebrew update belongs to this local candidate phase.
