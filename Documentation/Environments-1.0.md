# PkgLift 1.0 environment qualification

Status: **1.0 published on 2026-09-29 within the adopted evidence-bound
matrix.** The [final qualification](Qualification-1.0.md) distinguishes source
preparation, signed M acceptance and public distribution. Running the CLI,
compiling PkgLift and migrating/building a consumer remain separate workloads.
The dated evidence below is retained as history.

## Adopted initial 1.0 matrix

The initial host boundary is **Apple Silicon only**. The lowest observed signed
1.0 runtime host is **macOS 14.8.9 (23J631)**. The accepted M artifact, rather
than the historical 0.10 binary, passed on that host. No exact macOS 14.0 claim
or unobserved patch claim follows from deployment metadata.

| Cell | Qualified toolchain | Boundary |
| --- | --- | --- |
| G2-16 | Xcode 16.4 (16F6), Swift 6.1.2 (`swiftlang-6.1.2.1.2`) | Named hosted source/consumer cases at their own recorded commits; signed M full/partial/refusal acceptance. |
| G2-27 | Xcode 27.0 (27A266a), Swift 6.4 (`swiftlang-6.4.0.34.1`) | Historical source qualification bound by unchanged build inputs, plus separate signed M local runtime and four-consumer acceptance. |

These are independent cells, not a continuous supported range or a promise for
all newer Xcode/Swift versions. The external positive multi-target/workspace
cell remains deferred after 1.0; repository fixtures and refusals have the
narrower meanings recorded in the [scope contract](ScopeProposal-1.0.md).

## Final 1.0 evidence matrix

M is `207ff4e92b2fc4ed39c5fd8a4c2270eb0093faf9` and its accepted archive/binary hashes are
`402a8bec302af870ae6e86955e310e0b95cd2386123790e17924edf5946a84e1` /
`4e7997c6a03e19cf41d6413d90066dd17064f2975feddd066d5ef606556f998b`.
The M rows below all refer to these bytes. Each environment is captured in its
own job or local execution; a missing field is not supplied from another row.

| Cell/source | Exact observations | Actual result and evidence |
| --- | --- | --- |
| Signed M core runtime | macOS 14.8.9 (23J631), arm64; image `macos14` / `20260831.0302.1` | Signature/quarantine, version, registry, analyze, plan, dry run and structural apply passed. No consumer build. [M runtime job](https://github.com/Alexsvensson99/PkgLift/actions/runs/36615292778/job/109569158132), [receipt](Evidence/Qualification-1.0/cloud-final-M-acceptance.json). |
| Signed M consumer acceptance | macOS 15.7.9 (24G830), arm64; image `macos15` / `20260907.0337.1`; Xcode 16.4 (16F6), Swift 6.1.2 (`swiftlang-6.1.2.1.2`); CocoaPods 1.17.0; iOS Simulator SDK 18.5 (22F76); macOS SDK 15.5 (24F74) | Complete mixed migration/build, PartialMixed migration/build with retained KeychainAccess, Hammerspoon refusal. [M acceptance job](https://github.com/Alexsvensson99/PkgLift/actions/runs/36615292778/job/109569158059), [same-job receipts](Evidence/Qualification-1.0/cloud-final-M-acceptance.json). |
| Signed M local runtime and four consumers | macOS 27.0 (26A428), arm64; Xcode 27.0 (27A266a), Swift 6.4 (`swiftlang-6.4.0.34.1`); CocoaPods 1.17.0; iOS Simulator SDK 27.0 (24A430); macOS SDK 27.0 (26A425); `runnerImage: null` | Core runtime, PartialSwift, PartialMixed, PartialSwiftCoexistence and fresh full mixed migration/build passed with M's exact archive; Debug/arm64, iOS deployment 15.0. [Local acceptance](Evidence/Qualification-1.0/local-final-M-acceptance.json), [before](Evidence/Qualification-1.0/local-signed-M-environment-before.json), [after](Evidence/Qualification-1.0/local-signed-M-environment-after.json). The full case retains its failed iOS-9 baseline and separately bound iOS-15 retry. |
| Final source F consumer qualification | Source `1839cbfe614c3affeecd6c790bb43ca2053a334a`; each named consumer records macOS 15.7.9 (24G830)/arm64 and its own Xcode 16.4/Swift 6.1.2/SDK/CocoaPods capture | Seven repository-owned consumer cases passed. These use the F source pilot artifact, not the signed M archive. [F run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36610656058), [source receipt and artifact identities](Evidence/Qualification-1.0/source-qualification.json). |
| Historical local 1.0 source preparation | Intentionally dirty preparation based on `c5c32ee…`; macOS 27.0 (26A428), Xcode 27.0 (27A266a), Swift 6.4, CocoaPods 1.17.0 | 646 Swift tests, build/registry, API, recovery and partial-consumer evidence retain their original receipts. All 194 build inputs bind through F/M. [Historical source record](Qualification-1.0.md#local-source-preparation-2026-09-29), [binding](Evidence/Qualification-1.0/source-qualification.json). |
| Public M archive and Homebrew | Tag `v1.0.0` targets M; public archive SHA `402a8bec302af870ae6e86955e310e0b95cd2386123790e17924edf5946a84e1`; formula commit `2317ae83bc8e1095877c8f79bfd53dbc1b7945e3` | Public checksum/signature/binary and hosted Homebrew install/test/uninstall verified separately. Local strict audit was unavailable because Command Line Tools were outdated; no local installation was started. [Public readback](Evidence/Qualification-1.0/public-distribution.json), [formula](https://github.com/Alexsvensson99/homebrew-tap/blob/2317ae83bc8e1095877c8f79bfd53dbc1b7945e3/Formula/pkglift.rb). Package minimum `arm64`/macOS 14 and `:sonoma` are distribution policy, not proof of every 14.x runtime. |

## Current-main checkpoint on 2026-09-26

The [dated checkpoint](Qualification-2026-09-26.md) records a fresh default-engine
source build, 403 XCTest plus 233 Swift Testing tests, 25 mappings and a complete
PartialMixed migration on main `cbff61f…`, with exact local Xcode 27 metadata.
It also reconciles the historical matrix below: all three partial/coexistence
fixtures were subsequently main-qualified on `72f19b3…`. Those are historical
baselines. The later 2026-09-29 decision selected the matrix above. Its final M acceptance
is recorded separately; no support promise is inferred from this checkpoint alone.

## Historical evidence matrix

| Cell | Exact observations | Evidence and qualification boundary |
|---|---|---|
| Released 0.10 CLI, historical macOS 14 arm64 | macOS 14.8.9 (23J631), arm64, runner image 20260831.0302.1 | [Run 35079049127](https://github.com/Alexsvensson99/PkgLift/actions/runs/35079049127) passed exact artifact/binary hashes, strict signature, quarantine execution, version, bundled registry and fixture analysis with unchanged bytes. This proves only the observed 0.10/14.8.9 cell; it does not qualify the final 1.0 candidate or exact 14.0. |
| Released CLI, macOS 15 arm64 | macOS 15.7.9 (24G830), arm64; Swift 6.1.2 (`swiftlang-6.1.2.1.2`) used to build | [Signing run 35066758613](https://github.com/Alexsvensson99/PkgLift/actions/runs/35066758613), release commit `7d976d70e66a584e2e25db9852ac0e53bb6201b9`. Signature/notarization and quarantine CLI checks passed. Xcode 16.4 is selected by workflow; its build number was not printed in this job. |
| Released CLI, local macOS 27 arm64 | macOS 27.0 (26A428), arm64 | Fresh G2 checksum/signature/quarantine execution, version, 25 bundled mappings and read-only mixed-language fixture analysis passed. Fixture bytes were unchanged. This is CLI smoke evidence; no Gatekeeper `spctl` assessment or consumer build is claimed. |
| Source, baseline macOS 15 arm64 | macOS 15.7.9 (24G830), arm64 runner image 20260907.0337.1 | [Run 35056724222](https://github.com/Alexsvensson99/PkgLift/actions/runs/35056724222), source `cbb0eb1c2d385cbfce72bdc2b1e0f5e039fc0f1c`: 570 tests, builds and 25 mappings passed. Exact Xcode/Swift versions were not recorded in that source job. Do not fill its missing fields using another job's environment. |
| Source, local macOS 27 arm64 | macOS 27.0 (26A428), Xcode 27.0 (27A266a), Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS SDK 27.0 (26A425) | Historical G2 checks are recorded below. The Xcode 27/Swift 6.4 cell is now selected, but this older observation is not the final-candidate receipt. |
| Swift/iOS consumers, baseline | Xcode 16.4 (16F6), CocoaPods 1.17.0, iPhoneSimulator SDK 18.5 (22F76), Debug/generic iOS Simulator, deployment 15.0 | KeychainAccess, DeviceKit and CryptoSwift baseline/SwiftPM/migrated builds passed on source `cbb0eb1c…` in run 35056724222. Their artifacts record these versions but omit host OS/CPU/Swift. Both simulator architecture slices are not Intel-host evidence. |
| Swift + Objective-C consumer | SDWebImage job passed in run 35056724222 | The job result is recorded; a complete environment artifact is missing from the retained local evidence. Qualify the combined cell before expanding claims. |
| Retained CocoaPods + migrated SwiftPM | macOS 15.7.9 (24G830), arm64; Xcode 16.4 (16F6); Swift 6.1.2 (`swiftlang-6.1.2.1.2`); CocoaPods 1.17.0; iPhoneSimulator SDK 18.5 (22F76); Debug/arm64 iOS Simulator, deployment 15.0 | On main `9d2951…`, [PartialSwift](https://github.com/Alexsvensson99/PkgLift/actions/runs/35110617046/job/104844753608) and [PartialMixed](https://github.com/Alexsvensson99/PkgLift/actions/runs/35110617046/job/104844753582) passed baseline and post-migration builds, retained-pod refresh/lock checks and structural verification. This qualifies those historical repository-owned cells at that commit. All three fixture/coexistence cells and conflict-refusal coverage were subsequently main-qualified on `72f19b3…`; see [the complete partial-pilot record](PartialMigration-1.0.md#main-qualification-on-2026-09-16). Their final 1.0 counterparts are recorded in the matrix above; the external positive multi-target/workspace cell remains deferred. |

The public artifact in all released-CLI rows is version **0.10.0**, archive
SHA-256 `ad0747b3c10794ca93f23dc51953b3d234ddcfdabf4af1b5d4de5cd14876bd12`,
binary SHA-256 `9b3160a9853324a49a67f3022e8492326cf90b56fba4dfa01f31e2623d26fd00`.
Do not substitute the earlier private candidate or a newly compiled binary for
this exact historical released-artifact test. The independent final 1.0 acceptance
is recorded above.

## Reproducible environment records

Run `python3 Scripts/capture-environment.py > environment.json` from a checkout.
The helper finds the repository from its own location and records the commit,
tracked-change state, exact macOS build, CPU architecture, Xcode/Swift/CocoaPods
versions and SDK versions/builds. It uses bounded read-only probes, omits raw
stderr, home paths and environment variables, and marks unavailable, failed or
timed-out probes explicitly. An incomplete capture returns status 1 while still
writing JSON. On GitHub Actions, `runnerImage` records bounded `ImageOS` and
`ImageVersion` values; missing or invalid image data keeps the capture incomplete.
New local captures use `runnerImage: null`. The dated clean-main records below
predate this additive field and intentionally retain their original bytes.
`metadataOnly: true` means a complete capture proves no build or test.

Pair the record with the exact source commit, command/exit results and retained
logs from the same job. Record the runner image identifier in hosted jobs too.
Check the entire checkout before qualification: the helper's `trackedChanges`
field deliberately does not inventory untracked files. Any intentional patch or
exported source tree needs a separate byte-identity record.

Do not infer an SDK from an Xcode label, a compiler from `swift-tools-version`,
or host support from Mach-O deployment metadata. Record runtime evidence even
when no Xcode or CocoaPods installation is needed to run the released CLI.

## Local Xcode 27 investigation

Two independent issues were reproduced:

1. In the synchronized checkout, Finder metadata on generated `.xctest` and
   resource bundles causes Swift Build code signing to fail. Removing the
   attributes on generated bundles was insufficient: the metadata reappeared.
   A byte-matched source export with existing pinned dependencies under a fresh
   `/private/tmp` directory compiled and signed without this error. Use a
   non-synchronized build location; no filesystem/security settings were changed.
2. Swift Build produces macOS resources at
   `PkgLift_PkgLiftRegistry.bundle/Contents/Resources/BundledRegistry`.
   The old locator only handled the flat SwiftPM distribution layout. The
   locator now handles both layouts under the same existing candidate roots,
   preserving symlink resolution, deterministic precedence and typed refusal
   when no registry exists. This does not change mapping acceptance or AUTO.

The unfixed exported G1 source reproduced the missing-registry error. The fix
has regression coverage for flat/modern/missing layouts and precedence, plus
the public-library test loading the real bundled registry. Both the default
Swift Build engine (outside the sync directory) and native engine passed all
578 tests (354 XCTest and 224 Swift Testing), explicit builds and 25 bundled
mapping validations on source `bc40947617b7632ff95a5aad4c561f0a1d906863`.
The exported tree was byte-compared against all tracked source files.

Retained records: [environment](Evidence/Environments-1.0/local-environment.json),
[source results and log digests](Evidence/Environments-1.0/local-validation.json),
and [released CLI smoke](Evidence/Environments-1.0/released-cli-local-smoke.json).
These historical local records do not replace the separate protected CI or
final M artifact acceptance above. The temporary source/build copy occupies approximately
618 MiB and is retained for inspection; no cleanup was performed.

## GitHub runtime qualification

GitHub's [standard runner table](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
lists `macos-14` as arm64 and standard runners as free for public repositories.
PkgLift's repository is public. The runner label still must be checked against
the actual OS version and architecture at runtime; do not trust the label alone.
The [runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-14-arm64-Readme.md)
documented deprecation of that historical macOS 14 image. Continued maintenance qualification needs an available
environment for the observed macOS 14 floor; a runner label or its historical
availability does not establish a runtime result.

The bounded runtime workflow used read-only repository permissions and the
already published archive. It neither builds/signs a new release nor requires
signing secrets. Its result is evidence for its observed host patch version,
not a consumer-migration test or a complete G2 pass.

The first run [35079049127](https://github.com/Alexsvensson99/PkgLift/actions/runs/35079049127)
passed on workflow commit `d7b962c76abf2dc2018576918462aa0129421ea9`.
The downloaded [summary](Evidence/Environments-1.0/macos14-runtime-summary.json)
and [run/digest provenance](Evidence/Environments-1.0/macos14-runtime-provenance.json)
are retained here so artifact expiry does not erase the observation. Only the
runtime workflow ran; this is not protected source-build, consumer or CodeQL
acceptance of the branch. Its `qualifiesMinimumHost` field means the required
macOS 14/arm64 family in that historical workflow matched. It is not the adopted
1.0 runtime-floor decision and does not mean that 14.0 was exercised.

## Adopted decisions and maintenance boundaries

- Signed M passes the observed macOS 14.8.9/arm64 runtime cell; exact 14.0 is
  not inferred. Maintain fresh evidence when future releases change the artifact.
- Xcode 16.4/Swift 6.1.2 and Xcode 27.0/Swift 6.4 remain separate qualified
  cells. Do not interpolate versions or claim all later toolchains.
- Source qualification, signed archive acceptance, public readback and Homebrew
  tests have separate receipts in [final qualification](Qualification-1.0.md).
- The external positive multi-target/workspace case remains post-1.0 work. It
  cannot be closed by repository fixtures, source-only pilots or refusals.
