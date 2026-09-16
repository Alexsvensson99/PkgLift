# Repository-owned partial migration qualification

These pilots exercise a supported AUTO dependency alongside an explicitly retained
CocoaPods dependency. They extend G3 fixture coverage; they do not qualify arbitrary
upstream applications, all toolchains, or a signed 1.0 candidate.

| Fixture | Consumer | Migrates to SwiftPM | Remains on CocoaPods |
|---|---|---|---|
| [PartialSwift](../Fixtures/PartialSwift/README.md) | Swift | KeychainAccess 4.2.2 | SDWebImage 5.18.1 |
| [PartialMixed](../Fixtures/PartialMixed/README.md) | Swift and Objective-C | SDWebImage 5.18.1 | KeychainAccess 4.2.2 |

Both fixtures use the shipped registry and an explicit schema-1 `migration.deny`
policy for the retained dependency. This is a user policy refusal, not proof of
unmapped or external-source migration. No classifications or mappings are relaxed.
The mixed target imports SDWebImage from both Swift and Objective-C; its Swift
source also calls KeychainAccess. Neither pilot launches an app or simulator.

## Repeatable acceptance

From the repository root, with a built CLI and a **new** absolute output directory:

```sh
python3 Scripts/run-partial-migration-pilot.py \
  --case PartialSwift --output /absolute/new/partial-swift \
  --pkglift /absolute/path/to/pkglift --jobs 2
```

Repeat with `--case PartialMixed` and another new output directory. Existing output
paths and output paths within the source checkout are refused, not removed. Logs and dependencies stay in the task-owned copy.
CocoaPods and Xcode may use their normal external caches. Dependencies are pinned
in the fixture Podfiles and lockfiles. Installation uses `--deployment` before the
baseline and explicitly refreshes the remaining CocoaPods integration after apply.

The runner requires:

1. A successful baseline CocoaPods build with both pinned dependencies.
2. Exactly the reviewed AUTO set, expected target/language evidence, and a BLOCKED retained entry.
3. A byte-unchanged dry run, including hidden migration state.
4. Apply removes only the exact migrated Podfile declaration.
5. After refresh, only the retained root dependency remains locked and its lockfile matches `Pods/Manifest.lock`.
6. Exactly one SwiftPM reference, target product and framework link; CocoaPods base configurations and manifest-check phase remain attached.
7. A fresh build in a separate DerivedData directory, using the same consumer/configuration, plus structural verification and the exact reviewed SwiftPM revision.
8. Unchanged consumer sources/resources, deny configuration, and original fixture.

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

These two fixtures cover policy-retained dependencies in a single target. Existing
SwiftPM coexistence, conflicting-requirement refusal, multi-target/workspace
selection, real upstream migrations, exact lower host/toolchain boundaries and
signed release acceptance remain separate G2/G3/G6 gates in [the 1.0 plan](Plan-1.0.md).

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
