# PkgLift v0.6.0 Release Evidence

Status: **released on 2026-09-05 through GitHub and Homebrew.**
[PkgLift v0.6.0](https://github.com/Alexsvensson99/PkgLift/releases/tag/v0.6.0)
is public, with a Developer ID-signed, Apple-notarized archive. This record
separates the earlier S1 integration and local candidate checks from the
completed verification of the published artifact.

## Released contract

The released version is `0.6.0`, with the implementation integrated in
[`208ee39`](https://github.com/Alexsvensson99/PkgLift/commit/208ee391bd15c72289641718e60a70f62d2a1af4)
through [PR #84](https://github.com/Alexsvensson99/PkgLift/pull/84).
The [Stage 1 record](GeneratedPackageStage1Validation.md) binds its successful
seven main workflows and 21 commit checks to that exact implementation commit.
The later version/documentation preparation and final publication manifest
have their own commit and workflow evidence below.

The release implements only the synthetic, read-only S1 contract in
[GeneratedPackageEvidence.md](GeneratedPackageEvidence.md). The new API is
confined to `PkgLiftCocoaPods`; it does not generate a manifest, verify supplied
file contents, widen supported Podspec shapes or change automatic migration.
`Version.swift` identifies the release as `0.6.0`. The dated changelog and
[release notes](ReleaseNotes-0.6.0.md) record the publication date `2026-09-05`.

## Release provenance and completed gates

| Stage | Verified identity and result |
| --- | --- |
| Product preparation | [PR #85](https://github.com/Alexsvensson99/PkgLift/pull/85) merged as [`36e6c2e`](https://github.com/Alexsvensson99/PkgLift/commit/36e6c2e8bfa456da94919789d9d5b551ea9eadfe); its [positive pilot](https://github.com/Alexsvensson99/PkgLift/actions/runs/33932905929) passed on that exact commit. |
| Publication manifest | [PR #86](https://github.com/Alexsvensson99/PkgLift/pull/86) merged as [`8f99878`](https://github.com/Alexsvensson99/PkgLift/commit/8f998789d60f37734d07886fe8cee46391f8a3bd), the single direct child of the preparation commit, adding only `.github/releases/v0.6.0.json`. |
| Signed distribution | [Run 33951367655](https://github.com/Alexsvensson99/PkgLift/actions/runs/33951367655) passed on the manifest commit: 423 Swift tests, 22 registry mappings, arm64 build, Developer ID signing, Apple notarization `Accepted`, packaging and quarantined CLI checks. |
| Public tag and release | [Run 33951360035](https://github.com/Alexsvensson99/PkgLift/actions/runs/33951360035) passed after the protected publication approval. It created the lightweight `v0.6.0` tag and public release, then verified the tag and assets. Publication time was 2026-09-05 16:20:23 UTC. |
| Homebrew | [Tap PR #9](https://github.com/Alexsvensson99/homebrew-tap/pull/9) merged as [`35431a6`](https://github.com/Alexsvensson99/homebrew-tap/commit/35431a6351c3242d75296262201682ee77475153). Both the [PR check](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/33979307574) and [published-main check](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/33979469720) passed style, strict online audit, install, version, registry, signature, architecture, minimum macOS, formula test and uninstall verification. |

The release tag points exactly to
`8f998789d60f37734d07886fe8cee46391f8a3bd`. All seven core workflows and their
21 checks passed on this manifest commit:
[Build](https://github.com/Alexsvensson99/PkgLift/actions/runs/33951359763),
[Test](https://github.com/Alexsvensson99/PkgLift/actions/runs/33951359985),
[Quality](https://github.com/Alexsvensson99/PkgLift/actions/runs/33951359967),
[Registry Validation](https://github.com/Alexsvensson99/PkgLift/actions/runs/33951359782),
[CodeQL](https://github.com/Alexsvensson99/PkgLift/actions/runs/33951359769),
[Pinned Pilots](https://github.com/Alexsvensson99/PkgLift/actions/runs/33951359858)
and [Mixed-Language End-to-End Pilot](https://github.com/Alexsvensson99/PkgLift/actions/runs/33951359852).

## Published artifact

The release contains exactly
[`pkglift-macos-arm64.tar.gz`](https://github.com/Alexsvensson99/PkgLift/releases/download/v0.6.0/pkglift-macos-arm64.tar.gz)
and its
[SHA-256 file](https://github.com/Alexsvensson99/PkgLift/releases/download/v0.6.0/pkglift-macos-arm64.tar.gz.sha256).

- Archive size: **2,820,697 bytes**.
- Archive SHA-256: `87533df993ab31af4764eb4c15734b06a3a64364dd493d042a9b7d16333f4088`.
- Platform: Apple Silicon (`arm64`), macOS 14 or later.
- Payload: the executable and 22 registry resources, totaling 23 regular files.
- Signature: Developer ID with hardened runtime and secure timestamp;
  notarization returned `Accepted`.

Both public files were downloaded without authentication and matched the
accepted signed distribution byte for byte. The checksum file agrees with
the archive. The extracted CLI reports `0.6.0` through both `version` and
`--version`, and its adjacent registry validates all 22 mappings. The Homebrew
formula uses this exact archive checksum and preserves the adjacent bundle
behind a relative executable symlink.

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

## Historical local candidate acceptance

The local candidate built and audited from clean commit
`69ddba7173a3379c043dc9e4d5c0d6657ffa7bad` passed debug and arm64 release builds,
423 Swift tests, 26 release-policy tests and validation of all 22 registry
mappings. Its archive contains 23 regular files; tar and zip payload file
hashes match. Both extracted CLI version forms report `0.6.0`, and packaging
smoke checks passed for registry loading, installed-style symlink lookup and
typed missing-bundle refusal. The archive SHA-256 is
`a5def3251b48f9571cfa3fb70a68dc67e69dff46d7680a472cd26b43c2825e58`.
That earlier candidate was locally ad hoc-signed, without Developer ID signing
or notarization. Its checksum is historical local process evidence; the
published checksum and final distribution evidence are recorded above. The
subsequent date/status changes were documentation-only and did not change its
tested product sources.

For local reproduction of source and packaging checks, use a reviewed source
checkout and record the exact Git commit, compiler version, commands, results
and new artifact SHA-256 separately:

```bash
swift build -j 2
swift test -j 2
swift build -c release -j 2 --arch arm64
swift run --skip-build pkglift registry validate
ruby Scripts/validate-repository-yaml.rb
python3 -m unittest discover -s Tests/ReleaseManifestTests -p 'test_*.py'
git diff --check 208ee391bd15c72289641718e60a70f62d2a1af4 HEAD
COPYFILE_DISABLE=1 bash Scripts/package-release.sh release /path/to/a-new-local-rc-directory
```

Use a new, empty output directory for every packaging attempt.
`COPYFILE_DISABLE=1` omits macOS AppleDouble metadata from the local tar payload,
as verified for the local candidate. Where the local sandbox requires it, use
task-local SwiftPM/compiler cache paths and
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

## Scope after release

Source preparation, manifest review, signing/notarization, public tag/release
creation and Homebrew publication were completed as separate approved steps.
Future releases must repeat the applicable gates in the
[distribution workflow](Distribution.md). Publishing v0.6.0 does not authorize
a later release or expand the S1 contract into package generation or migration.
