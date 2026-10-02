# PkgLift 1.0.1 — Project-format safety and dependency maintenance

PkgLift 1.0.1 was published on **2026-10-02 Europe/Stockholm**
(`2026-10-01T23:31:14Z`) as
[GitHub release v1.0.1](https://github.com/Alexsvensson99/PkgLift/releases/tag/v1.0.1).
Tag `v1.0.1` targets final manifest commit
`030b8a21d936a96e76090ca39ac78dd68c4df51c`. The accepted public archive and
binary SHA-256 values are respectively
`eaee546af04f11df66d1f16cbbbf66dea881969e0dd34795d1a5b74e65b9e591` and
`b7409899d57ed6e90c4afaa11c46e29da85a889eb5ec7028189191c2c4cb8173`.

The immutable
[Homebrew formula](https://github.com/Alexsvensson99/homebrew-tap/blob/0f1faf8805b00c575f1989075235b3609c89a7ea/Formula/pkglift.rb)
uses the same verified public archive.

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

They entered final source F,
`76dd1f9712f9e5da3609bacc26e0d0022e2ae290`, through
[PR #142](https://github.com/Alexsvensson99/PkgLift/pull/142). Manifest-only
[PR #143](https://github.com/Alexsvensson99/PkgLift/pull/143) made M the sole
direct child of F and bound the release to successful exact-F main pilot run
`36764966069`.

## Compatibility and upgrade

The CLI, JSON and six-library public API contracts and positive support
boundaries remain unchanged. XcodeProj 9.17.5 required fresh binary acceptance;
the new signed-M evidence replaces no historical 1.0.0 record. JSON-project
migration and positive external multi-target/workspace migration were not added.
No classification or migration safety check is weakened.

Regenerate analysis and executable plans with 1.0.1 before dry run or apply,
including plans created by 1.0.0. Do not edit producer-version or evidence fields
to reuse an older plan.

## Exact-candidate release acceptance

| Gate | Verified result |
| --- | --- |
| Source F | All 30 reported checks passed, including [main pilot 36764966069](https://github.com/Alexsvensson99/PkgLift/actions/runs/36764966069) and [G3 run 36765095908](https://github.com/Alexsvensson99/PkgLift/actions/runs/36765095908). [Receipt](Evidence/Qualification-1.0.1/source-qualification.json). |
| Signed M package | [Release run 36769614583](https://github.com/Alexsvensson99/PkgLift/actions/runs/36769614583), attempt 1, passed tests, registry validation, release build, Developer ID signing, notarization and quarantined CLI verification. [Receipt](Evidence/Qualification-1.0.1/cloud-final-M-acceptance.json). |
| Hosted signed-M consumers | Full mixed migration/build, PartialMixed migration/build retaining KeychainAccess, and protected-source/index-preserving Hammerspoon refusal passed on the accepted binary. Planning may add `.pkglift/plan.json`; the subsequent dry run was mutation-free. [Receipt](Evidence/Qualification-1.0.1/cloud-final-M-acceptance.json). |
| Signed-M macOS 14 runtime | Signature/quarantine, version, registry, analyze, plan, dry run and structural apply passed on macOS 14.8.9. No consumer build ran there. [Receipt](Evidence/Qualification-1.0.1/cloud-final-M-acceptance.json). |
| Local signed-M acceptance | Core runtime, PartialSwift, PartialMixed, PartialSwiftCoexistence and full mixed migration/build passed on macOS 27/Xcode 27 using the same accepted archive. [Receipt](Evidence/Qualification-1.0.1/local-final-M-acceptance.json). |
| Public distribution | Publication run `36769590339` completed successfully. Public tag/release/assets, strict signature, version `1.0.1`, 25 registry mappings and all three accepted hashes were read back successfully. [Receipt](Evidence/Qualification-1.0.1/public-distribution.json). |
| Homebrew | [PR #18](https://github.com/Alexsvensson99/homebrew-tap/pull/18) merged as `0f1faf8805b00c575f1989075235b3609c89a7ea`. [PR CI 36942357174](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/36942357174) and [main CI 36942559400](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/36942559400), both attempt 1, passed Apple Silicon, tap setup, style, audit, install, installed verification, formula test and uninstall. No local install or audit was performed for 1.0.1. |

The public archive, binary and registry-bundle tree match the private candidate
accepted by both cloud and local qualification. The registry-bundle tree SHA-256
is `14e6d8975c87f7ad88b6d92bd43319662db9a43893f134ca0000abf0234e5510`.

## Observed environments

| Workload | Exact observed environment |
| --- | --- |
| Signed-M runtime | macOS 14.8.9 (23J631), arm64; image `macos14` / `20260831.0302.1`. No consumer build. |
| Hosted signed-M consumers | macOS 15.7.9 (24G830), arm64; image `macos15` / `20260907.0337.1`; Xcode 16.4 (16F6); Swift 6.1.2 (`swiftlang-6.1.2.1.2`); CocoaPods 1.17.0; iOS Simulator SDK 18.5 (22F76); macOS SDK 15.5 (24F74). |
| Local signed-M consumers | macOS 27.0 (26A428), arm64; Xcode 27.0 (27A266a); Swift 6.4 (`swiftlang-6.4.0.34.1`); CocoaPods 1.17.0; iOS Simulator SDK 27.0 (24A430); macOS SDK 27.0 (26A425); `runnerImage: null`. |
| F G3 qualification | macOS 15.7.9, arm64; Xcode 16.4; Swift 6.1.2; CocoaPods 1.17.0. |

These are separate observations, not a continuous Xcode range or proof that
exact macOS 14.0 was exercised. See the
[environment evidence](Environments-1.0.md#101-maintenance-evidence-2026-10-02)
and [complete qualification record](Qualification-1.0.1.md).

The [1.0.0 release record](ReleaseNotes-1.0.0.md),
[compatibility policy](API-1.0.md) and
[distribution procedure](Distribution.md) retain the baseline process and
historical evidence.
