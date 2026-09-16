# Repository-owned partial migration qualification

These pilots exercise a supported AUTO dependency alongside an explicitly retained
CocoaPods dependency. They extend G3 fixture coverage; they do not qualify arbitrary
upstream applications, all toolchains, or a signed 1.0 candidate.

| Fixture | Consumer | Migrates to SwiftPM | Remains on CocoaPods |
|---|---|---|---|
| [PartialSwift](../Fixtures/PartialSwift/README.md) | Swift | KeychainAccess 4.2.2 | SDWebImage 5.18.1 |
| [PartialMixed](../Fixtures/PartialMixed/README.md) | Swift and Objective-C | SDWebImage 5.18.1 | KeychainAccess 4.2.2 |
| [PartialSwiftCoexistence](../Fixtures/PartialSwiftCoexistence/README.md) | Swift, with existing SwiftPM DeviceKit 5.8.0 | KeychainAccess 4.2.2 | SDWebImage 5.18.1 |

All fixtures use the shipped registry and an explicit schema-1 `migration.deny`
policy for the retained dependency. This is a user policy refusal, not proof of
unmapped or external-source migration. No classifications or mappings are relaxed.
The mixed target imports SDWebImage from both Swift and Objective-C; its Swift
source also calls KeychainAccess. The coexistence fixture begins with DeviceKit
5.8.0 already linked through SwiftPM, with its pinned package reference, product,
framework link and `Package.resolved` pin. It migrates KeychainAccess 4.2.2 while
retaining SDWebImage 5.18.1; those pre-existing DeviceKit objects and pin must
remain unchanged against the runner's captured baseline state. Neither pilot
launches an app or simulator.

## Repeatable acceptance

From the repository root, with a built CLI and a **new** absolute output directory:

```sh
python3 Scripts/run-partial-migration-pilot.py \
  --case PartialSwift --output /absolute/new/partial-swift \
  --pkglift /absolute/path/to/pkglift --jobs 2
```

Repeat with `--case PartialMixed` and `--case PartialSwiftCoexistence`, each with
another new output directory. Existing output paths and output paths within the
source checkout are refused, not removed. Logs and dependencies stay in the task-owned copy.
CocoaPods and Xcode may use their normal external caches. Dependencies are pinned
in the fixture Podfiles and lockfiles. Installation uses `--deployment` before the
baseline and explicitly refreshes the remaining CocoaPods integration after apply.

The runner requires:

1. A successful baseline CocoaPods build with both pinned dependencies.
2. Exactly the reviewed AUTO set, expected target/language evidence, and a BLOCKED retained entry.
3. A byte-unchanged dry run, including hidden migration state.
4. Apply removes only the exact migrated Podfile declaration.
5. After refresh, only the retained root dependency remains locked and its lockfile matches `Pods/Manifest.lock`.
6. Exactly one SwiftPM reference, target product and framework link for each expected package; CocoaPods base configurations and manifest-check phase remain attached.
7. A fresh build in a separate DerivedData directory, using the same consumer/configuration, plus structural verification and the exact reviewed SwiftPM revisions.
8. Unchanged consumer sources/resources, deny configuration, and original fixture.
9. For the coexistence case, the baseline DeviceKit 5.8.0 package reference,
   product, framework link and resolved pin remain unchanged while KeychainAccess
   is added.

Both builds explicitly use Debug, arm64 iOS Simulator, iOS deployment target 15.0,
and disabled signing. The deployment override is required by Xcode 27 because the
upstream podspecs still default to iOS 9. It applies equally before and after
migration; it does not modify the dependency source or expand the support promise.

Each `report/summary.json` identifies the binary and fixture hashes, repository
commit/working-tree state, build settings and outcome. Environment metadata and
individual build, analysis, plan, apply, verification and lockfiles are retained
alongside it. A failure leaves `status: incomplete`; a green dry run alone cannot
satisfy the pilot.

## Remaining scope

The first two fixtures cover policy-retained dependencies in a single target.
The third fixture and conflict-refusal tests have local qualification below;
their exact-PR CI and protected integration remain separate requirements.
Multi-target/workspace selection, real upstream migrations, exact lower
host/toolchain boundaries and signed release acceptance remain separate G2/G3/G6
gates in [the 1.0 plan](Plan-1.0.md).

## Local qualification on 2026-09-16

Both complete pilots passed on macOS 27.0 (26A428), arm64, Xcode 27.0
(27A266a), Swift 6.4 and CocoaPods 1.17.0, using the iOS Simulator 27.0 SDK
(24A430) and explicit iOS 15.0 deployment settings. Fresh post-migration logs
contain the Swift compilation steps in both cases and Objective-C compilation
for `LegacyImageLoader.m` in the mixed case.

- [Swift summary](Evidence/PartialMigration-1.0/PartialSwift-summary.json) and
  [environment](Evidence/PartialMigration-1.0/PartialSwift-environment.json).
- [Mixed-language summary](Evidence/PartialMigration-1.0/PartialMixed-summary.json) and
  [environment](Evidence/PartialMigration-1.0/PartialMixed-environment.json).

The product source baseline is `f29f2663cb899fd3905a2194519e62d61f22573a`.
The summaries bind the new, then-uncommitted fixture and runner bytes by SHA-256
and correctly report a dirty working tree. The environment capture's aggregate
`incomplete` status reflects those uncommitted changes; all individual host and
toolchain probes passed. Native-engine debug build, 578 Swift tests, 107 Python
tests (15 focused pilot guard tests), all 25 registry mappings, YAML/pinned-action
validation and documentation file links passed. The CLI binary was byte-identical
before and after the confirming source build.

The first attempted unmodified CocoaPods baseline failed because Xcode 27 rejects
the pods' iOS 9 deployment settings. The recorded success is specifically the
explicit iOS 15 build configuration above. It does not establish that the original
podspec defaults build on Xcode 27. No new GitHub Actions result or release is
claimed by this local evidence.

## Ordinary CI integration

The ordinary [pilot workflow](../.github/workflows/positive-e2e.yml) runs all three cases
on macOS 15/Xcode 16.4. Each consumes the same source-bound, checksum-verified CLI
artifact produced by the build job. The three cases run serially; no additional
PkgLift compilation is introduced. Each uses separate baseline and post-migration
DerivedData directories and uploads its report even when the pilot fails.

The existing `Mixed-Language Pilot Gate` requires the original mixed-language
pilot **and all three partial-migration cases** to succeed. Failure, cancellation,
skipping or missing jobs cannot satisfy the gate. Repository policy tests protect
the matrix, exact runner invocation, artifact checks and dependency on all cases.
CI results for this change must be read from its exact PR head; the local Xcode 27
evidence above does not substitute for the hosted Xcode 16.4 runs.

## Main qualification on 2026-09-16

PR [#119](https://github.com/Alexsvensson99/PkgLift/pull/119) merged as
[`9d2951fb8e2d8bc2326cc4cb7c9e41f0ba9d78cf`](https://github.com/Alexsvensson99/PkgLift/commit/9d2951fb8e2d8bc2326cc4cb7c9e41f0ba9d78cf).
Its reviewed PR tree and main tree matched. The main check collection contains
24 completed, successful checks, including [PartialSwift](https://github.com/Alexsvensson99/PkgLift/actions/runs/35110617046/job/104844753608),
[PartialMixed](https://github.com/Alexsvensson99/PkgLift/actions/runs/35110617046/job/104844753582),
the [ordinary quality workflow](https://github.com/Alexsvensson99/PkgLift/actions/runs/35110617040)
and [CodeQL](https://github.com/Alexsvensson99/PkgLift/actions/runs/35110617119).

The retained main artifacts bind both pilots to that commit with `trackedChanges:
false` and complete metadata: macOS 15.7.9 (24G830), arm64, Xcode 16.4 (16F6),
Swift 6.1.2, CocoaPods 1.17.0 and iPhoneSimulator SDK 18.5 (22F76). Their
`summary.json` status is `passed`; each structural report verifies the expected
SwiftPM package/product/target link and removal of only the migrated pod.

This main result qualifies the two original repository-owned fixture cells described here.
It does not qualify the subsequently added existing SwiftPM coexistence fixture,
conflicting-requirement refusal,
multi-target/workspace selection, arbitrary upstream projects, an exact macOS 14.0
runtime, or a signed 1.0 release candidate. Those remain the separate G2/G3/G6
gates listed in [the 1.0 plan](Plan-1.0.md).

## Coexistence and conflicting-requirement qualification on 2026-09-16

The new `PartialSwiftCoexistence` pilot passed locally with the corrected CLI on
macOS 27.0 (26A428), arm64, Xcode 27.0 (27A266a), Swift 6.4 and CocoaPods
1.17.0. Baseline and fresh post-migration Debug/arm64 simulator builds passed
with iOS deployment target 15.0. DeviceKit 5.8.0 remained linked and pinned to
`56b997e8a61707218f9af09f32b2a1d1806fd792`; KeychainAccess 4.2.2 migrated,
and SDWebImage 5.18.1 remained on CocoaPods. The pilot verified unchanged
existing package objects, existing pins, consumer bytes and retained integration.

Retained records: [summary](Evidence/PartialMigration-1.0/PartialSwiftCoexistence-summary.json),
[environment](Evidence/PartialMigration-1.0/PartialSwiftCoexistence-environment.json),
and [validation/source/log hashes](Evidence/PartialMigration-1.0/PartialSwiftCoexistence-local-validation.json).
These describe an uncommitted working tree based on main `9d2951f`, with the
fixture, runner and binary identified by hashes. The environment aggregate is
`incomplete` because of tracked changes; every environment probe passed. This
is local qualification, separate from exact-PR CI and future release acceptance.

Conflict regression tests cover initial REVIEW/no-op apply, rejection of a
saved AUTO plan after a conflict appears, and duplicate references to the same
normalized repository with differing or unknown requirements. Previously only
the first reference was checked; analysis and editing now inspect every match.
The new editor regression failed against the old implementation with two missing
refusal assertions. With the fix, all 583 Swift tests (359 XCTest and 224 Swift
Testing), 131 Python policy/helper tests, native build and 25 registry mappings
passed. Refusal tests check that project, Podfile, lockfile, source and saved-plan
bytes stay unchanged, with no migration marker or backup created. This is
refusal evidence, not a successful-build claim for conflicting projects.
