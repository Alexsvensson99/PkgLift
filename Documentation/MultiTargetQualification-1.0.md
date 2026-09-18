# Multi-target real-project qualification for 1.0

Status: **bounded candidate screen complete; no positive multi-target result**.
Reviewed against main `6dcfc7bf5b2bcc0f8654e920c6ce7fd57767b986` on 2026-09-18.
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
current classifier retains review for `use_frameworks!`, installation hooks,
abstract targets and unsupported statements, including a literal `source` line.
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
