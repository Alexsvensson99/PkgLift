# Multi-target real-project qualification for 1.0

Status: **Scheme discovery and baseline compilation passed; baseline source preservation failed, migration not reached**.
Latest hosted result: main `38dc4ed041cfbb235582775cbbab6b602b82292b` on 2026-09-19.
The earlier design review used main `6dcfc7bf5b2bcc0f8654e920c6ce7fd57767b986` on 2026-09-18.
The existing [selected G3 cases](RealProjectQualification-1.0.md) passed on that
main commit in [run 35149953474](https://github.com/Alexsvensson99/PkgLift/actions/runs/35149953474).
Those results remain one positive AWS partial migration and two intentional
refusals. They do not prove a positive migration preserves sibling native targets.

## Target selection contract

PkgLift has `--project` and `--workspace`, not `--target`. The executable plan
must prove exactly one destination target for each AUTO dependency through the
literal Podfile declarations and the selected project graph. A pod attributed to
multiple targets remains subject to conservative review; a qualification runner
must not edit the plan or select a subset of its AUTO actions by hand.

A positive case must contain at least two existing native targets. The intended
consumer must have a supported, exactly resolved registry dependency attributed
to it alone. Sibling targets must already exist upstream; adding synthetic targets
to an upstream app would be fixture evidence, not this real-project shape.

The initial screen requires a pinned public source revision, a reviewed license,
a committed lockfile and an unchanged Podfile that passes the current classifier.
Static-looking Ruby is not automatically supported syntax. In particular, the
classifier retains review for `use_frameworks!`, installation hooks, abstract
targets and unsupported statements. The new [bounded public-source contract](StaticPublicSpecSource.md)
accepts one exact official Specs Git source only with matching lock evidence.
The historical screens below predate that support.
Missing locked versions cannot be replaced with an assumed latest version.

## Bounded source survey

Three GitHub code searches for `SDWebImage`, `Alamofire` and `SnapKit` in
Podfiles returned 100 results each. After deduplication by repository, commit and
path, the source screen attempted 277 immutable files: 100, 92 and 85 respectively.
It read 276 within a 32 KiB limit; one SDWebImage result remained unread. This
was a bounded heuristic intake screen, not an exhaustive ecosystem survey or
PkgLift analysis of every repository.

Fourteen SDWebImage Podfiles survived the initial syntax screen. Only
[`NgGithubIos` at `e6c4392`](https://github.com/jiangzhengnan/NgGithubIos/tree/e6c4392363a9a5250c3023124b095a3a1b5578df)
also had a committed compatible SDWebImage lock (5.11.1), but its project had
only one native target. The Alamofire and SnapKit searches yielded no syntax
survivor; neither advanced to lockfile, license or project-graph review.
Active `use_modular_headers!` alone was not rejected. No positive case was
accepted, and no upstream installation or build was run for this survey.

## Source-only Stay assessment

The [Stay revision `f4e2fdb`](https://github.com/shenruisi/Stay/tree/f4e2fdbecc34a0c5250eabaa59b73096a7b7e674)
is the parent of the later commit adding a second app target. Its original
project has `Stay`, `StayTests`, `StayUITests` and `Stay Extension`; the Podfile
names only `Stay`. The source is MPL-2.0. Inspection found Objective-C app sources,
a CocoaPods manifest-check shell phase and no SwiftPM package references.

**Stay is rejected as a positive candidate under the current contract.** It has
no committed `Podfile.lock`, and its literal
`source 'https://github.com/CocoaPods/Specs.git'` statement is outside the parser's
modeled-statement allowlist. The actual analysis produces:

| Dependency | Classification | Reasons |
|---|---|---|
| SDWebImage | `REVIEW` | `podfile_dynamic_ruby`, `resolved_version_invalid` |
| InterAppCommunication | `UNKNOWN` | `registry_mapping_missing`, `podfile_dynamic_ruby`, `resolved_version_invalid` |

The [screening record](Evidence/MultiTargetQualification-1.0/stay-screening.json)
binds the source files, CLI binary hash and portable analysis hash. It uses the
previously accepted 0.10.0 executable, not a freshly built main executable. The
Podfile parser, classifier and `Registry/` mapping data have no source changes
between the 0.10.0 release and the reviewed main commit. `RegistryLoader.swift`
has a later resource-layout compatibility change; this record does not claim
the two executables are identical. All 470 checked-out source files still
match their pinned Git blob content and executable modes, with no extra files.

Only PkgLift read-only analysis ran locally. No upstream Ruby, dependency install,
application, build, plan apply or GitHub qualification run was executed for Stay.
A generated dependency lock would be new qualification input and would not solve
the independent unsupported-source-statement refusal.

## Supporting editor regression

`XcodeProjectEditorTests.testLinkingProductToAppPreservesSiblingTargetAndExistingProjectReferences`
uses a controlled two-target fixture. It links Alamofire to the app and checks
the serialized project for exactly one app link and no sibling link, while
preserving the sibling's existing package and project references. This exercises
the editor's target isolation; it does not prove upstream baseline builds,
migration orchestration or CocoaPods refresh behavior. It is fixture evidence,
not a positive real-project G3 result.

Local validation on 2026-09-18 passed 360 XCTest cases and 224 Swift Testing
cases with `swift test --build-system native --disable-automatic-resolution --jobs 4`.
The 192 release-policy tests, repository YAML checks and registry validation
(25 mappings) also passed. Swift 6.4's default `swiftbuild` attempt failed during
local test-bundle signing with a resource-fork/Finder-metadata error, before test
execution; the successful run used the existing native SwiftPM cache. This does
not establish compatibility with the default build engine or hosted CI results
for this change.

## Required positive execution evidence

For a subsequently accepted candidate, review the complete dependency and build
input closure before installation. Bind the upstream revision, lockfile, exact
podspecs, source revisions, package manifests, licenses, generated scripts and
scheme actions. Record the same environment and same-run artifact provenance as
the existing manual G3 harness. Use disposable hosted copies and unsigned generic
simulator builds; launching apps or accessing live services is outside this test.

1. Build the unchanged dependency configuration in an independent baseline copy.
   Include the selected app, any embedded extension, and compilation of sibling
   test targets through an existing scheme's build-for-testing action where
   available. A missing or failing baseline is inconclusive.
2. In a separate migration copy, confirm the exact complete AUTO set and target
   attribution. Require a clean worktree and prove dry run leaves the source,
   ignored files, symlinks, executable modes and Git index unchanged.
3. Apply the unedited plan. Validate exact package, version, product and owning
   target. The new product must be linked exactly once to the intended consumer
   and zero times to each sibling target.
4. Compare all sibling target objects, configuration lists and settings, source,
   resource, framework and copy phases, target dependencies, proxy references,
   existing package products, entitlements and bundle settings. Shared project
   metadata must change only through the precisely reviewed dependency additions.
   Do not normalize away all targets' package products or shell phases.
5. Refresh CocoaPods explicitly and repeat the full ownership/preservation checks.
   Verify retained versions, payloads and generated build scripts before the final
   build. CocoaPods changes must be accounted for separately from PkgLift writes.
6. Run structural verification and fresh baseline-equivalent builds. Confirm the
   built app embeds the expected extension and package resources. Keep test
   compilation distinct from actually executing tests or launching a simulator.
7. Publish only portable qualification evidence identifying exact inputs, commands,
   binary identity, target-level results and the complete reviewed change scope.
   A green command alone does not establish sibling preservation or G3 completion.

The existing AWS runner requires exactly one native target. Do not relax that
assertion globally to reuse it for an unrelated source. A new selected case needs
its own reviewed target inventory and preservation checks before hosted execution.

## Selected ZBNetworking execution protocol

[`Suzhibin/ZBNetworking` at `fda54d347a0a8be11cf63e5eea76d0289e3a728d`](https://github.com/Suzhibin/ZBNetworking/tree/fda54d347a0a8be11cf63e5eea76d0289e3a728d)
is the selected MIT-licensed case. Its unchanged Podfile and committed lock attribute
SDWebImage 5.8.4 and AFNetworking 4.0.1 only to `ZBNetworkingDemo`. The project
already contains `ZBNetworkingDemoTests` and `ZBNetworkingDemoUITests`.
The new local classifier produces exactly one AUTO entry, SDWebImage, with the
exact locked version; unmapped AFNetworking remains on CocoaPods. The
[portable analysis](Evidence/MultiTargetQualification-1.0/zb-portable-analysis.json)
and [local validation record](Evidence/MultiTargetQualification-1.0/zb-local-screening.json)
bind that result and prove analysis left the source-tree snapshot unchanged.
On a separate disposable local copy, the unedited plan and dry run passed; apply
changed only Podfile, project.pbxproj and its backup. The new product links once
to the app and zero times to either sibling. Sibling object closure, protected
project state, user schemes and breakpoints are preserved. No upstream Ruby,
CocoaPods refresh or Xcode build ran locally. The first hosted attempt is recorded below.

The [execution intake](Evidence/MultiTargetQualification-1.0/zb-execution-intake.json)
binds the full upstream Git tree, target identifiers, existing schemes, executable
phase, original lock, exact public podspec bytes, dependency commits and Swift
package manifest. The separate manual
[`G3 Multi-Target Qualification`](../.github/workflows/multi-target-qualification.yml)
uses [`run-real-project-zb.py`](../Scripts/run-real-project-zb.py); the existing AWS
one-target assertion remains unchanged.

Baseline and migrated copies use the same Xcode 16.4, CocoaPods 1.17.0, Debug,
generic iOS Simulator `build-for-testing` command with explicit
`IPHONEOS_DEPLOYMENT_TARGET=15.0`. The upstream app itself sets 13.0; test targets
inherit the project's older 7.0 setting. The qualification therefore establishes
compilation under the controlled iOS 15 profile only. It cannot establish original
minimum-OS compatibility, runtime behavior or executed tests. All three app/test
products must be produced from fresh, separate build outputs.

The upstream schemes are committed under another user’s `xcuserdata`. The runner
copies one reviewed scheme byte-for-byte to the shared scheme directory in both
copies, records and commits that exact harness-only setup delta, and then takes
the qualification snapshots. No target or action is generated. Baseline means
pinned upstream plus this identical scheme promotion. An unavailable scheme or
failing baseline is inconclusive. No upstream Podfile source rewrite, version change or
synthetic target may be used to manufacture a positive result. The runner checks
one app package link, zero sibling links, complete sibling object closure,
protected source/resource/settings state, exact Podfile removal, dry-run file and
Git invariance, retained AFNetworking payload and lock, and structural verification.
The two pinned public podspecs form a bounded local Specs-cache projection;
CocoaPods refresh disables repository updates and network access.

Only `report/` may be uploaded. Source, logs, caches and build products remain
private job-local material. Positive hosted qualification remains pending; this protocol does
not close G3 or authorize a release.

Local verification of this preparation passed 378 XCTest cases and 233 Swift
Testing cases, 212 Python harness/policy tests, registry validation (25 mappings),
and repository YAML/workflow validation. An independent source-contract review
found no actionable issues.
The editor now writes only `project.pbxproj`, avoiding unrelated scheme and
breakpoint reserialization discovered by the real-project apply check.

Plans carrying registry-source provenance use schema 2 so released schema-1
library preflights reject them before operations. The local real-project check
was repeated with the full and portable schema-2 plans and the complete framework
phase/dependency-proxy preservation checks.

## First hosted attempt and diagnostic follow-up

[PR #124](https://github.com/Alexsvensson99/PkgLift/pull/124) integrated the protocol
at `45c26db3434f9dc7bba369859a0e313cff940748`. The single authorized
[run 35396091852, attempt 1](https://github.com/Alexsvensson99/PkgLift/actions/runs/35396091852)
finished with a failed G3 gate. Both refusal controls passed using the same
verified executable; ZBNetworking stopped with `failed-safety: scheme discovery mutated source`.
The [portable result record](Evidence/MultiTargetQualification-1.0/zb-first-hosted-run.json)
binds the source commit, binary, runner, report hashes and observed stage.

On macOS 15.7.9 arm64 with Xcode 16.4, both pinned copies passed source intake
and identical byte-for-byte scheme promotion. Baseline `xcodebuild -list -json`
exited 0 and its selected-scheme check passed, but the subsequent tree snapshot
differed. No baseline build, PkgLift migration, CocoaPods refresh or final build
ran. No app or tests launched. The original short-circuit guard did not collect
the changed paths, post-list index or worktree status. The specific changed path
and cause were unknown in that run; this is neither a successful migration nor evidence
that PkgLift caused the change.

The diagnostic follow-up collects all three postconditions before checking them
and retains `schemeDiscovery` in the final report even when the guard raises.
It records tree and Git-output hashes, change flags, total changed-path count,
and up to 64 relative paths with kinds, modes, sizes and hashes. Path display is
bounded to 1,024 characters with a full-path hash; Xcode user-directory names are
redacted and symlink targets are represented only by hashes. File contents and
raw Git output remain private. Acceptance still requires an unchanged complete
tree, identical index and clean worktree; there is no new mutation allowlist,
cleanup or automatic retry. The subsequent hosted run below identified the delta.

Local follow-up verification passed all 217 Python harness/policy tests, including
five new discovery-diagnostic tests, plus repository YAML/workflow and whitespace
checks. Independent review found no actionable issues. This follow-up changes
only the Python runner, its tests and evidence/docs; Swift sources are unchanged.

## Hosted diagnostic result and bounded directory setup

[PR #125](https://github.com/Alexsvensson99/PkgLift/pull/125) merged at
`8a936c2e299419fdcc1140d730926e3d35b5f4e8` after all 26 checks passed.
[Run 35409428336, attempt 1](https://github.com/Alexsvensson99/PkgLift/actions/runs/35409428336)
again stopped before baseline build or migration. Both refusal controls passed.
This time the [diagnostic record](Evidence/MultiTargetQualification-1.0/zb-directory-diagnostic-run.json)
shows the complete delta: two added directories, both mode `0777`, beneath
`ZBNetworkingDemo.xcworkspace/xcshareddata/`:

- `swiftpm`
- `swiftpm/configuration`

No files were added, removed or modified. The parent contains only the
`configuration` directory, whose contents are empty. The Git index was unchanged
and Git status was clean. Directory entries are included in the runner's snapshot
even though Git does not track empty directories, so the strict guard correctly
stopped. This is Xcode setup metadata, not a PkgLift migration delta.

The follow-up prepares exactly these paths in both disposable copies after scheme
promotion and before discovery. It requires real directory parents, absent setup
paths, an exact two-directory delta and mode `0777` independent of umask, unchanged
Git index and clean status. The report records both setup snapshots and the runner
requires identical preparation evidence in both copies. No placeholder files,
directory commits, source edits or removal/normalization are performed. This setup
is explicitly bound in the updated execution intake. Mode `0777` reproduces only
the observed directories inside the disposable private job copies.

The discovery, baseline and migration preservation checks retain their complete
snapshots. Any later file, mode, index or status change still fails. The setup
subsequently passed on GitHub as recorded below; complete baseline qualification
and post-migration builds remain unverified.

Local verification passed all 223 Python harness/policy tests and repository YAML/whitespace
checks. Six new tests cover exact setup, umask, existing entries, symlinked parents,
unexpected files, post-setup mutation refusal and mismatched-copy evidence. A local
setup-only check on two disposable copies of the pinned real project produced the
exact same before/after tree hashes as the hosted diagnostic. The original source
remained unchanged; no Xcode or CocoaPods command ran locally. Independent review
found no remaining implementation or test-gate issue.

## Hosted baseline compilation and probe-preservation failure

[PR #126](https://github.com/Alexsvensson99/PkgLift/pull/126) merged at
`38dc4ed041cfbb235582775cbbab6b602b82292b` after all 26 checks passed.
In [run 35441212940, attempt 1](https://github.com/Alexsvensson99/PkgLift/actions/runs/35441212940),
both copies received identical directory preparation and both scheme-discovery
checks passed with zero tree or index changes and clean Git status. The
[portable result record](Evidence/MultiTargetQualification-1.0/zb-baseline-probe-run.json)
binds these results, the executable and the remaining failure.

All six baseline settings commands exited 0 with the expected iOS 15 deployment
settings. `build-for-testing` exited 0 and produced the app, unit-test bundle and
UI-test bundle. The build's own before/after source and index guard passed.
However, the outer source checkpoint taken before the settings commands differed
after the build, so the run stopped with `failed-safety: baseline probes/build
changed prepared source`. This narrows the unexplained delta to the settings-probe
interval; it does not identify the exact command or changed paths. The report
does not contain that delta, so no new directory or file is assumed safe.

Baseline compilation is proven under the controlled profile; baseline source
preservation and positive migration qualification are not. No PkgLift migration,
CocoaPods refresh, post-migration build, app launch or test execution occurred.
Both refusal controls passed using the same verified executable.

The next diagnostic follow-up records bounded before/after tree, index and status
evidence around scheme discovery, each settings probe, and each baseline/final
build, including when the command fails. A proven mutation is `failed-safety` even
if Xcode also fails; unchanged failed commands retain their original outcome.
A settings mutation now stops before the next Xcode command. Aggregate settings and baseline evidence survive inner failures
in the final report. Status is compared exactly with its pre-command value, so
the reviewed dirty state after migration is accepted only if it remains unchanged.
The baseline must match its recorded prepared-tree hash and have clean Git status
before any settings or build command. The outer baseline also retains its clean-status requirement. No accepted mutation,
source preparation or dependency input is added by this diagnostic change.

All 229 Python harness/policy tests and repository YAML/whitespace checks pass
locally. Six new test methods cover independent tree/index/status changes, early
stopping, unchanged dirty state, failed-command safety precedence, changed-baseline
preflight refusal and persisted aggregate evidence.
Swift sources are unchanged. The hosted observer result follows below.


## Hosted settings diagnosis and app workspace preparation

[PR #127](https://github.com/Alexsvensson99/PkgLift/pull/127) merged at
`af49faf95dec12ef0dd5faf6710d0a8d636f176b` after all 26 checks passed.
[Run 35443019152, attempt 1](https://github.com/Alexsvensson99/PkgLift/actions/runs/35443019152)
stopped immediately after `baseline-ZBNetworkingDemo-settings`. The command
exited 0 but created exactly two directories, both mode `0777`, inside the app
project's existing workspace:

- `ZBNetworkingDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm`
- `ZBNetworkingDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration`

The [portable diagnostic record](Evidence/MultiTargetQualification-1.0/zb-settings-diagnostic-run.json)
contains the complete bounded delta and artifact identity. No files or Git index
entries changed and Git status remained clean. Both discovery checks passed with
zero changes. The new immediate guard stopped before any sibling/Pods settings
probe, baseline build or migration. Both refusal controls passed with the same
binary and source commit. G3 remains open.

The local follow-up adds only this observed pair to the existing outer-workspace
preparation. Both copies receive the same four sorted directory entries before
Xcode runs. Every pre-existing ancestor must be a real directory, every setup
path must be absent, and the resulting delta must contain exactly the four
mode-`0777` directories with no files or Git changes. Both configuration leaves
remain empty. Complete tree, index and status guards remain active for every
later probe and build. No Pods workspace metadata is pre-created: that workspace
is absent upstream and its probe behavior remains unobserved.

Local verification passed 231 Python harness/policy tests, repository YAML and
whitespace checks. Coverage includes each existing setup path and symlinked
ancestor, missing parents, mode independence, unexpected files and Git mutation.
Two disposable copies of the pinned project produced identical preparation
records and the exact hosted post-probe tree digest
`d60b75d6ae0cf86e567f2fa7d6241d38da2f453e51a9817b8eb61fb12a187cd1`.
Only Git and setup helpers ran locally; no Xcode, CocoaPods or upstream code ran.
The extension has not yet been qualified on GitHub. A later unknown mutation
will still stop the run and retain evidence.


## Hosted apply result and CocoaPods Specs-layout diagnosis

[PR #128](https://github.com/Alexsvensson99/PkgLift/pull/128) merged at
`26618525c934999784e54f0f6ca18481f67f8dd8` after all 26 checks passed. The
project-write-rule review was resolved as an explicitly approved, directory-only
qualification-fixture exception; production mutation rules were unchanged.

[Run 35444656493, attempt 1](https://github.com/Alexsvensson99/PkgLift/actions/runs/35444656493)
passed both refusal controls, identical four-directory preparation, all six
baseline settings probes and baseline `build-for-testing`. All 11 recorded source
checks had zero tree, index or Git-status changes. The app and both test products
were produced. Analysis, planning, dry run and PkgLift apply exited 0. Reaching the
next CocoaPods command establishes by control-flow inference that the preceding
sibling, protected-project, linkage, exact Podfile and apply-delta assertions
passed; those post-apply states were not separately serialized in the summary.

CocoaPods then exited 1 before final verification or build. Its 306-byte stdout
was omitted from the portable report. The [run and local diagnostic receipt](Evidence/MultiTargetQualification-1.0/zb-cocoapods-diagnostic-run.json)
binds the executable, source and exact output hashes. Both refusal controls use
the same binary, source commit, registry, run and attempt. G3 remains open.

An isolated local reproduction used CocoaPods 1.17.0, the pinned upstream copy,
reviewed podspec bytes, the existing local PkgLift binary, and the same
network-denying sandbox. It emitted exactly the hosted stdout hash
`4921b61aa4b446c22568865628b6db7f0461ab7fe50301a0692fd7ee57c8befb`:
CocoaPods could not find the AFNetworking specification. No Xcode build, package
resolution, app launch or test execution ran locally.

The generated Specs repo omitted `CocoaPods-version.yml`. CocoaPods therefore
used an unprefixed layout while the pinned specs were stored in three hash-prefix
directories. The [official metadata at the already pinned Specs commit](https://raw.githubusercontent.com/CocoaPods/Specs/e4af897aa0ddc011a5adc30aa3568aa6ae2ab600/CocoaPods-version.yml)
declares `prefix_lengths: [1, 1, 1]`; its exact SHA-256 is
`4d1dc0966425cdd834073ff6852045975d08bf63fd500bfaa0cad2795506c713`.
Adding only those bytes made the same offline `pod install` complete locally.
The fix seeds and commits the metadata alongside the two original podspecs and
binds it in the execution intake. The generated repo remains a local projection;
only its selected bytes are pinned to the official Specs commit, not its Git HEAD.

The local continuation also proved CocoaPods' source-locking behavior. It removed
owner-write permission from the 14 retained AFNetworking source files: thirteen
`0644 -> 0444` transitions and one `0755 -> 0555`, with identical paths, kinds,
content hashes and sizes. CocoaPods 1.17.0 `PodSourceInstaller#lock_files!` applies
`chmod('u-w', ...)`; it does not remove other write or executable bits. The original
full descriptor digest is
`46b246ffa903b939afb8c97185f4475a3740de1ed498706788325f6856788698` and the exact
locked digest is
`302af4b95d030153d4cbd86ac886b27eb0b3b5384cf440778ee3663cd32e3d35`.

The follow-up validates this exact candidate-specific transition only after a
successful CocoaPods refresh. It preserves actual tree descriptors and separately
reports the reviewed and expected locked digests. Baseline validation and the
pre-refresh migration delta guard remain unchanged. Extra/missing paths, content
changes, different modes, kind changes and executable-bit changes remain errors;
no file is chmodded back and no mode is ignored globally. Local sibling/protected
project checks and PkgLift structural verification passed after the refresh.
Final hosted package resolution and post-migration compilation remain unverified.

Local follow-up validation passed all 239 Python harness/policy tests (44 ZB tests),
repository YAML and whitespace checks. The updated seeding helper produced a Git
cache containing exactly the two original specs and the pinned metadata file.
The updated payload helper also accepted the actual locally refreshed AF tree
against both pinned descriptor digests. No hosted rerun has been dispatched.
