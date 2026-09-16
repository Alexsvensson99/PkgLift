# Real-project qualification protocol for 1.0

Status: **manual harness integrated; first hosted attempt failed before AWS execution**. Protocol reviewed on
2026-09-16 against PkgLift main
[`72f19b3e3163d401b57950d02bd5fc191328ce2a`](https://github.com/Alexsvensson99/PkgLift/commit/72f19b3e3163d401b57950d02bd5fc191328ce2a).
This is the next G3 work package in [the 1.0 plan](Plan-1.0.md#g3--prove-real-and-partial-migrations).
It does not change the ten [read-only pilots](Pilots.md), authorize upstream
execution, or declare G3 complete. Only source files and repository metadata were
inspected for this selection. No upstream installation, build or migration was run.
The [intake manifest](Evidence/RealProjectQualification-1.0/intake.json) records
exact source URLs and SHA-256 digests of the inspected files, with every execution
status set to `not-run`.

## Manual harness

The separate [G3 workflow](../.github/workflows/real-project-qualification.yml)
has only `workflow_dispatch`; ordinary PR, main and scheduled pilots remain
unchanged. It builds and verifies one same-run PkgLift/registry artifact, runs both
[refusal controls](../Scripts/run-real-project-refusal.py), and permits the
[AWS runner](../Scripts/run-real-project-aws.py) only after both controls succeed.
An always-running final gate requires all three jobs to succeed. Failed or skipped
phases cannot satisfy it.

All consumer jobs use disposable hosted macOS 15/arm64 with Xcode 16.4. The AWS
runner requires CocoaPods 1.17.0 and rejects toolchain drift rather than installing
an unreviewed replacement. Git checkout disables inherited configuration, hooks
and attribute filters. Every external command has a timeout. Only selected,
portable reports are uploaded; source copies, raw project/lock data and build
directories remain outside the upload paths.

The [execution intake](Evidence/RealProjectQualification-1.0/execution-intake.json)
records immutable dependency specifications, archive and manifest hashes, and the
remaining runtime checks. The [CocoaPods validator](../Scripts/validate-real-project-cocoapods.rb)
compares both generated scripts with exact output from hash-pinned generator
templates and validated framework metadata. It also binds the app/Pods phase
bodies, owners and complete input/output file lists. These checks must pass before
either build; offline tests do not claim that future generated inputs already pass.

The Amazon 1.40.0 archive was downloaded and inspected as data: its declared
SHA-256, 138-entry inventory and two declared Mach-O slices passed. Generator
reconstruction also passed against its real framework metadata. This does not
authenticate the binary signatures or establish buildability.

Offline regression tests are under `Tests/ReleaseManifestTests/test_real_project*.py`.
They exercise acceptance guards and the workflow boundary, not upstream buildability.
On 2026-09-16, all 185 release/harness Python tests passed; repository YAML
validation passed for 12 files, eight pinned workflows and two issue forms.
Ruby syntax and reconstruction using real framework metadata also passed.
The harness must first be reviewed and integrated, then explicitly dispatched at
the reviewed ref. No hosted run, successful AWS migration, new G3 qualification
result or public release is claimed by its implementation.

## First hosted attempt

[PR #121](https://github.com/Alexsvensson99/PkgLift/pull/121) integrated the
harness as `c736332c3b2c9a1720cadbd41d059d7a122ab185` after successful PR checks.
[Run 35141250484](https://github.com/Alexsvensson99/PkgLift/actions/runs/35141250484)
verified its CLI artifact and passed the FirebaseUI refusal control. Hammerspoon
stopped before analysis because template-free `git init` does not create
`.git/info`; AWS was correctly skipped. No AWS installation, baseline build or
migration occurred, and G3 remains open.

Both runners now create the local Git exclusion directory before recording the
generated plan path. A regression initializes actual template-free repositories,
checks both runners, and verifies that only the generated plan is ignored. All
187 release/harness tests pass locally. Hosted verification of this fix is pending.

[The second attempt](https://github.com/Alexsvensson99/PkgLift/actions/runs/35143324501),
on correction commit `b2a1acb`, passed both refusal controls and reached AWS intake.
AWS then stopped before installation because the checkout validator expected one
privacy-resource symlink across the entire SDWebImage repository; the pinned tree
contains one for SDWebImage and another for SDWebImageMapKit. The validator now
binds both exact paths and their reviewed target/hash while retaining SDWebImage
as the selected product. Hosted verification of that correction remains pending.

## Selected cases

These are three distinct projects from three independent repositories. One is a
positive migration candidate; two are intentional refusal controls. They are not
three successful migrations. Existing read-only classifications inform the
expectations below; the future qualification run must establish its own results
against an identified PkgLift executable and registry.

| ID | Pinned source and license | Selection | Role and required outcome |
|---|---|---|---|
| `aws-grid-feed` | [aws-samples/amazon-ivs-grid-feed-for-ios-demo](https://github.com/aws-samples/amazon-ivs-grid-feed-for-ios-demo/tree/5573a57d4cb7e10f7ad86f95c548ddfbeabc6e1d), `5573a57d4cb7e10f7ad86f95c548ddfbeabc6e1d`; MIT-0 | Root `.`; `Grid Feed.xcodeproj`; explicit `Grid Feed.xcworkspace`; app target `Grid Feed` | Swift app and partial migration. Exact AUTO set must be only `SDWebImage 5.18.1`. Retain `AmazonIVSPlayer 1.40.0` and functional CocoaPods integration. Baseline and post-migration builds are required. |
| `firebaseui-project` | [firebase/FirebaseUI-iOS](https://github.com/firebase/FirebaseUI-iOS/tree/c30af73fee50724dcd9a3acf70548d3e58c86dc7/samples/swift), `c30af73fee50724dcd9a3acf70548d3e58c86dc7`; Apache-2.0 | Root `samples/swift`; explicit `FirebaseUI-demo-swift.xcodeproj`; no workspace | Project-only selection with an app and nested test target. Zero AUTO actions; local pods remain BLOCKED and `Firebase/Auth` remains REVIEW. Read-only analysis/plan/dry-run only. |
| `hammerspoon-workspace` | [Hammerspoon/hammerspoon](https://github.com/Hammerspoon/hammerspoon/tree/23e387e2805a9890066366e0ac96c71b27f0cfd5), `23e387e2805a9890066366e0ac96c71b27f0cfd5`; MIT | Root `.`; explicit `Hammerspoon.xcodeproj` inside `Hammerspoon.xcworkspace`, alongside `LuaSkin/LuaSkin.xcodeproj` and `Pods/Pods.xcodeproj` | macOS/Objective-C and multi-project workspace selection. Ten direct identities, zero AUTO actions, dynamic Ruby/post-install refusal and conservative external Git provenance. Read-only analysis/plan/dry-run only. |

### AWS: positive candidate, not a qualified build

The pinned [Podfile](https://github.com/aws-samples/amazon-ivs-grid-feed-for-ios-demo/blob/5573a57d4cb7e10f7ad86f95c548ddfbeabc6e1d/Podfile)
uses literal declarations in the app target, without `use_frameworks!` or a
`post_install` hook. The [lockfile](https://github.com/aws-samples/amazon-ivs-grid-feed-for-ios-demo/blob/5573a57d4cb7e10f7ad86f95c548ddfbeabc6e1d/Podfile.lock)
records AmazonIVSPlayer 1.40.0 and SDWebImage/Core 5.18.1, with CocoaPods 1.16.2.
The Podfile declares iOS 14; the app project declares iOS 15 and Swift 5. Keep
these values unchanged. Two shell phases in the app project are CocoaPods' lock
check and framework embedding. Their generated implementations still require
inspection after installation.

No shared scheme is committed. `Grid Feed` is the expected implicit scheme,
supported by the historical [v0.2.0 run](https://github.com/Alexsvensson99/PkgLift/actions/runs/31860034938),
but a new authorized baseline must confirm it with `xcodebuild -list -json`.
Missing or ambiguous discovery is a blocker; do not silently synthesize a scheme.
That old run is historical evidence, not acceptance for the current executable.

AmazonIVSPlayer remains a vendored binary dependency. Its 1.40.0 podspec declares
`https://player.live-video.net/1.40.0/AmazonIVSPlayer.tgz` with SHA-256
`e7cacfbcaead184d0efca1c53d656d64ee2a46721b9097198848156a5476c5d6`.
This is the expected archive digest from the specification, not proof that an
archive was downloaded or verified in this planning step. The sample's MIT-0
license does not replace the player's separate license. Record and inspect both
dependency specifications and applicable licenses before execution. Do not launch
the app or use a live video service, credentials, signing identity or paid resource.

### FirebaseUI: preserve the refusal boundary

The pinned [Podfile](https://github.com/firebase/FirebaseUI-iOS/blob/c30af73fee50724dcd9a3acf70548d3e58c86dc7/samples/swift/Podfile)
contains `use_frameworks!`, four local pods using `:path => '../../'`, and a nested
test target with `inherit! :search_paths`. There is no committed lockfile, workspace
or shared scheme under this sample root. The project has app and unit-test targets;
the app declares iOS 17/Swift 6. Its setup also expects a user-supplied
`GoogleService-Info.plist`.

Select the project explicitly, without a workspace argument. Do not install pods,
create service configuration, resolve the local pod graph, build, or apply. The
acceptance result is accurate project/target discovery, the expected conservative
classifications and unchanged source bytes. This does not qualify a Firebase
migration or a successful multi-target migration.

### Hammerspoon: preserve workspace selection and provenance refusal

The pinned [workspace](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/Hammerspoon.xcworkspace/contents.xcworkspacedata)
contains both app and LuaSkin projects. Shared `Hammerspoon` and `Release` schemes
exist, but neither is executed in this case. The
[Podfile](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/Podfile)
declares macOS 13 and dynamic post-install logic. The project also has custom
phases for a secrets header, version numbers, documentation and a certificate
template, in addition to CocoaPods phases. Source inspection is not authorization
to run any of them.

Require exactly ten direct dependency identities and no AUTO entries in analysis
and plan. In particular, CocoaHTTPServer must retain `external_git_unpinned` and
Sentry `external_git_evidence_incomplete`, consistent with
[the existing pilot validator](../Scripts/validate-pinned-pilot.rb). Confirm that
the explicit app project is selected within the workspace and that neither the
LuaSkin project nor any other source changes. This establishes refusal/selection
coverage, not macOS build or migration support.

## Execution boundary and environment

The next execution proposal is bounded to **one AWS baseline/partial migration
and two read-only controls**, in disposable hosted GitHub macOS runners. Preserve
the existing ten-case workflow and its upstream apply prohibition; implement a
separate opt-in harness. Its implementation is now prepared under the subsequent
implementation approval. Workflow dispatch, upstream execution, GitHub writes and
release actions have not been performed by this preparation.

Use the already qualified macOS 15/arm64, Xcode 16.4 lane as the first proposed
cell. Record actual OS build, architecture, Xcode/Swift/SDK, Ruby and CocoaPods
versions; runner labels alone do not prove an environment. Pin tooling for the
attempt and reject unintended toolchain substitution. This does not close the
separate macOS 14.0 lower-bound G2 question.

Use disposable job storage, least-privilege `contents: read`, no repository secrets,
no signing, no upstream write credentials and no app/simulator launch. Download
the immutable PkgLift executable/registry artifact in a separate trusted step,
verify its hashes and source SHA, and do not leave checkout credentials available
to upstream build phases. Serialize costly builds, with per-command timeouts and
a bounded job timeout. Preserve selected reports rather than whole source trees,
Pods, DerivedData or private service configuration.

Before the AWS baseline can execute, complete static intake of the exact fetched
source and dependency closure: Podfile/podspec Ruby, `prepare_command` and script
phases, Xcode build phases and scheme actions, SwiftPM manifests/plugins,
submodules/LFS, download URLs, licenses and secret requirements. Inspect generated
CocoaPods phases again before the first build. Record what was reviewed; do not
label the current limited intake a complete dependency execution audit. Unexpected
scripts or floating source references require review, not silent execution.

## Positive-case procedure

Follow [the real-project testing guide](RealWorldTesting.md), with these additional
evidence requirements. The future runner must log exact argument arrays, exit
codes and durations. Commands below describe phases; they are not an executable
script or evidence of a completed run.

1. Fetch the exact AWS commit into two independent disposable copies. Verify HEAD
   and clean tracked/index/untracked state. Preserve an immutable upstream source
   record and hashes of source, resources, Podfile, lockfile, project and workspace.
   Do not update the pin or remove unsupported syntax to obtain AUTO.
2. In the baseline copy, install the locked dependencies without updating them
   (`pod install --deployment` where compatible), confirm the exact two versions
   and equality of `Podfile.lock` and `Pods/Manifest.lock`, then discover the scheme.
   Record any CocoaPods-generated metadata changes separately. A metadata mismatch
   is investigated, not silently accepted with dependency updates.
3. Build `Grid Feed` in `Grid Feed.xcworkspace`, Debug, generic iOS Simulator,
   `CODE_SIGNING_ALLOWED=NO`, in a baseline-only DerivedData directory. Record any
   overrides and apply the same ones to the final build. A failing or unavailable
   baseline yields `inconclusive-baseline` and stops the positive path.
4. Prepare the migration copy using the same reviewed dependency inputs. If setup
   changes tracked metadata, review and record an explicit setup checkpoint before
   PkgLift runs; keep the original upstream SHA and patch separately. Never hide
   these changes with `--allow-dirty`. Keep build outputs and reports outside the
   worktree. Add the exact `.pkglift/plan.json` path to `.git/info/exclude` using
   [the guide's procedure](RealWorldTesting.md#3-keep-the-generated-plan-from-dirtying-the-worktree),
   not the entire `.pkglift/` directory. Require empty `git status --porcelain
   --untracked-files=all` before planning and again after plan generation.
5. Run `analyze` and `plan` with explicit `--path`, `--project` and `--workspace`.
   Capture executable and portable reports separately. Require the complete AUTO
   set to equal only SDWebImage, version 5.18.1, mapped to the correct package,
   product and `Grid Feed` target. AmazonIVSPlayer must remain non-AUTO. Do not edit
   the plan or classifications. A changed classification or nonempty post-plan Git
   status stops apply for review; the local exclude must not conceal other files.
6. After plan generation, snapshot the full source tree including ignored source
   files, symlink targets and executable bits; separately record Git/index state.
   Run `migrate` without `--apply`. Require identical snapshots and an exact match
   between proposed actions and the reviewed plan. Exclude only external reports
   and Git-internal bookkeeping from the byte comparison.
7. Apply the reviewed plan to the clean migration copy with `migrate --apply`.
   Inspect the complete delta immediately. Only the reviewed SDWebImage dependency
   and related package/project objects may change; retained pods, unrelated
   settings, targets, existing package references, source and resources must survive.
8. Explicitly refresh CocoaPods with `pod install`, preserving AmazonIVSPlayer
   1.40.0 and its checked specification/archive identity. Review every lockfile and
   workspace change. Confirm SDWebImage/Core is absent from the remaining Pods
   graph, the manifest agrees with the lock, and retained framework integration
   survives. The post-migration lock change is expected; a retained version change
   is not.
9. Run structural `verify` with the same explicit selection. Resolve packages and
   run a fresh `xcodebuild` for workspace `Grid Feed.xcworkspace`, scheme `Grid Feed`,
   Debug, generic iOS Simulator and `CODE_SIGNING_ALLOWED=NO`, using a separate
   DerivedData directory and the baseline settings. Capture resolution and build
   logs, so cached objects cannot stand in for compilation. This direct build is
   the final build gate; do not add a redundant build solely to call `verify --build`
   (the current CLI does not expose arbitrary signing build settings). Confirm SDWebImage
   resolves exactly to 5.18.1, its product links exactly once to the app, and both
   SDWebImage and the retained Amazon player consumer compile.
10. Compare original, setup and migrated trees. Account separately for PkgLift and
    dependency-tooling changes. Require protected source/resource/settings hashes
    to match, retaining full reviewable diffs. The independent baseline remains
    available for recovery; PkgLift's internal backup does not cover later
    `pod install` or build side effects.

## Read-only control procedure

Use the exact roots and selectors in the matrix. Fetch and inspect without
submodule initialization, dependency installation or upstream script execution.
Record the same executable/source/environment identities as the positive case.
Run only PkgLift analysis, plan and migration dry-run. Keep the generated plan
locally excluded and snapshot after plan creation so its intended creation is
distinct from dry-run mutation. Require matching analysis/plan identities and
classifications, zero AUTO actions, and unchanged full source tree/index/Git state.

Never call `--apply`, `pod install`, `xcodebuild`, upstream scripts or app launch
for these two controls. A zero exit code alone is insufficient: verify the intended
project selection, expected refusal reasons and absence of mutation. Unexpected
AUTO is a safety failure, not an opportunity to expand the run.

## Evidence and completion decision

Each case report must include case ID; exact upstream SHA/license; selected root,
project/workspace/target/scheme (or `not-run`); PkgLift source/version/executable and
registry hashes; actual environment; reviewed dependency inputs; commands and exit
codes; analysis/plan/action sets; source/index snapshots; and redacted logs/diffs.
The positive case additionally needs baseline/final build results, package pins,
retained-pod checks and preservation checks. Report all unrun phases explicitly.

Use distinct outcomes: `passed-migration`, `passed-refusal`,
`inconclusive-baseline`, `blocked-input`, `failed-safety` or `failed-migration`.
An infrastructure failure must not count as a refusal pass. Nothing in this
document currently has an execution outcome. Publish only reviewed portable
reports without local usernames, credentials or copied upstream sources.

The selection meets the proposed three-case/two-repository floor structurally.
G3 remains open until evidence exists for every promised workflow/shape. The two
controls cannot substitute for a positive multi-target migration or prove a
successful migration in a second independent repository. If AWS cannot produce a
clean baseline, record its blocker and find a replacement before claiming positive
real-project qualification. Further positive cases are required wherever the
support contract promises shapes this set does not exercise.

LoodosCase was not selected for execution because no license was detected at its
existing pin. Other surveyed projects used `use_frameworks!`, dynamic Ruby or
post-install hooks and would add refusal coverage rather than a credible second
positive case. Leave those semantics intact and keep existing read-only pilots
unchanged.
