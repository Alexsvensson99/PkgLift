# PkgLift 1.0 environment qualification

G2 work in progress, 2026-09-16. This evidence inventory implements the
[1.0 plan](Plan-1.0.md) environment work package; it is not a 1.0 release
or a promise of universal support. Running a distributed executable, compiling
PkgLift and migrating/building a consumer project are separate qualifications.

## Evidence matrix

| Cell | Exact observations | Evidence and qualification boundary |
|---|---|---|
| Released CLI, macOS 14 arm64 | Pending exact runner observation | The artifact has minimum deployment metadata 14.0. The bounded GitHub runtime job must pass on an actual 14.x/arm64 host. A passing 14.x patch does not prove every earlier 14.x patch. |
| Released CLI, macOS 15 arm64 | macOS 15.7.9 (24G830), arm64; Swift 6.1.2 (`swiftlang-6.1.2.1.2`) used to build | [Signing run 35066758613](https://github.com/Alexsvensson99/PkgLift/actions/runs/35066758613), release commit `7d976d70e66a584e2e25db9852ac0e53bb6201b9`. Signature/notarization and quarantine CLI checks passed. Xcode 16.4 is selected by workflow; its build number was not printed in this job. |
| Released CLI, local macOS 27 arm64 | macOS 27.0 (26A428), arm64 | Fresh G2 checksum/signature/quarantine execution, version, 25 bundled mappings and read-only mixed-language fixture analysis passed. Fixture bytes were unchanged. This is CLI smoke evidence; no Gatekeeper `spctl` assessment or consumer build is claimed. |
| Source, baseline macOS 15 arm64 | macOS 15.7.9 (24G830), arm64 runner image 20260907.0337.1 | [Run 35056724222](https://github.com/Alexsvensson99/PkgLift/actions/runs/35056724222), source `cbb0eb1c2d385cbfce72bdc2b1e0f5e039fc0f1c`: 570 tests, builds and 25 mappings passed. Exact Xcode/Swift versions were not recorded in that source job. Do not fill its missing fields using another job's environment. |
| Source, local macOS 27 arm64 | macOS 27.0 (26A428), Xcode 27.0 (27A266a), Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS SDK 27.0 (26A425) | Current G2 checks are recorded below. This is a development observation, pending protected integration and an explicit 1.0 source-support decision. |
| Swift/iOS consumers, baseline | Xcode 16.4 (16F6), CocoaPods 1.17.0, iPhoneSimulator SDK 18.5 (22F76), Debug/generic iOS Simulator, deployment 15.0 | KeychainAccess, DeviceKit and CryptoSwift baseline/SwiftPM/migrated builds passed on source `cbb0eb1c…` in run 35056724222. Their artifacts record these versions but omit host OS/CPU/Swift. Both simulator architecture slices are not Intel-host evidence. |
| Swift + Objective-C consumer | SDWebImage job passed in run 35056724222 | The job result is recorded; a complete environment artifact is missing from the retained local evidence. Qualify the combined cell before expanding claims. |
| Retained CocoaPods + migrated SwiftPM | Pending | A successful partial consumer build with exact environment evidence remains required across G2/G3. Read-only pilots and single-pod fixtures do not close this cell. |

The public artifact in all released-CLI rows is version **0.10.0**, archive
SHA-256 `ad0747b3c10794ca93f23dc51953b3d234ddcfdabf4af1b5d4de5cd14876bd12`,
binary SHA-256 `9b3160a9853324a49a67f3022e8492326cf90b56fba4dfa01f31e2623d26fd00`.
Do not substitute the earlier private candidate or a newly compiled binary for
this exact released-artifact test. A future 1.0 candidate needs its own acceptance.

## Reproducible environment records

Run `python3 Scripts/capture-environment.py > environment.json` from a checkout.
The helper finds the repository from its own location and records the commit,
tracked-change state, exact macOS build, CPU architecture, Xcode/Swift/CocoaPods
versions and SDK versions/builds. It uses bounded read-only probes, omits raw
stderr, home paths and environment variables, and marks unavailable, failed or
timed-out probes explicitly. An incomplete capture returns status 1 while still
writing JSON. `metadataOnly: true` means a complete capture proves no build or test.

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
These local records do not replace protected CI or the future candidate's
artifact acceptance. The temporary source/build copy occupies approximately
618 MiB and is retained for inspection; no cleanup was performed.

## GitHub runtime qualification

GitHub's [standard runner table](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
lists `macos-14` as arm64 and standard runners as free for public repositories.
PkgLift's repository is public. The runner label still must be checked against
the actual OS version and architecture at runtime; do not trust the label alone.
The [runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-14-arm64-Readme.md)
also documents macOS 14 image deprecation, so retaining an alternate future test
environment remains necessary while that support boundary is advertised.

The bounded runtime workflow uses read-only repository permissions and the
already published archive. It neither builds/signs a new release nor requires
signing secrets. Its result is evidence for its observed host patch version,
not a consumer-migration test or a complete G2 pass.

## Remaining decisions and gates

- Complete the macOS 14 hosted runtime observation and retain its result.
- Choose exact lower/upper source-toolchain cells after evidence review. The
  current local Xcode 27 result must not silently become “all newer Xcode”.
- Record a complete environment alongside each promised consumer build,
  including the retained-CocoaPods partial case shared with G3.
- Preserve the advertised macOS 14 boundary unless a separate support decision
  changes it. A hosted later 14.x observation alone does not establish 14.0.
- Review/integrate changes through protected checks and repeat exact release
  acceptance for the future 1.0 artifact at G6.
