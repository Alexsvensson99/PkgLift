# PkgLift 1.0 plan: a verified support and compatibility contract

Status: planning complete; G1 compatibility contract is implemented and locally verified.
G2 environment qualification is in progress; G3–G6 and public 1.0 release qualification remain open.
Reviewed on 2026-09-16 against main `51d90970cebbd4612881fc101e5570145783e500`.
The public baseline is [0.10.0](https://github.com/Alexsvensson99/PkgLift/releases/tag/v0.10.0),
release commit `7d976d70e66a584e2e25db9852ac0e53bb6201b9`.
This document proposes acceptance criteria; it does not declare 1.0 ready or change current support.

## Outcome and scope

Make the existing Analyze → Plan → dry run → Apply → Verify workflow dependable
within an explicit, tested support envelope. A successful partial migration must
preserve dependencies that still need CocoaPods. Unsupported inputs must retain
their conservative classifications and useful explanations.

The [roadmap quality bar](../ROADMAP.md#v10-quality-bar) remains the release standard.
The first work package is the support/compatibility contract below, followed by
evidence for each promised workflow. Adding more registry identities is not a
substitute for these gates.

Recommended boundaries for this plan:

- Retain Apple Silicon distribution and the current macOS 14 minimum as the
  starting proposal. Record tested host and toolchain combinations before making
  a 1.0 support promise; a Mach-O deployment target alone is not runtime evidence.
- Preserve exact mapping, target, language, platform, version and live-preflight
  requirements. Swift, Objective-C and mixed targets remain mapping-dependent.
  Detection of Objective-C++, C or C++ does not imply automatic migration support.
- Retain the exact PkgLift-version requirement for executing saved plans. An
  upgrade requires regeneration even when the JSON schema remains readable.
  Cross-version apply is not a prerequisite for 1.0.
- Keep generated-package APIs and local source-inspection reports separate from
  migration authority. No new package generation, Ruby execution, external-source
  migration, platform expansion or automatic recovery command is included by default.

## Evidence and gaps at the baseline

“Established” below means a baseline capability or recorded result, not fresh
qualification of a future 1.0 binary. “Gap” means missing coverage or an unresolved
support promise, not a demonstrated implementation defect.

| Roadmap requirement | Established evidence | Remaining 1.0 gate |
|---|---|---|
| Stable plan schema or explicit compatibility policy | [JSON contracts](JSONSchema.md), schema 1, additive inspection compatibility and exact `pkgLiftVersion` equality in [preflight](../Sources/PkgLiftMigration/MigrationPlanPreflight.swift). Older incomplete AUTO entries are refused. | G1: [versioned compatibility policy](Compatibility-1.0.md) and focused examples/tests are locally verified. Protected integration remains; G6 must freeze the exact release API baseline. |
| Supported host/toolchain matrix | [Ordinary CI](../.github/workflows/positive-e2e.yml), [CodeQL](../.github/workflows/codeql.yml) and [release CI](../.github/workflows/release.yml) use macOS 15 with Xcode 16.4. [Distribution](Distribution.md) advertises arm64 macOS 14+. | G2: validate the lower host boundary and every advertised toolchain cell; distinguish binary execution from source compilation and project migration. |
| Broad real-project coverage | [Ten pinned upstream pilots](Pilots.md) exercise analysis, planning, inert dry run and conservative outcomes. Amazon IVS full migration is historical v0.2.0 evidence. Current recurring full apply/build runs use repository-owned fixtures. | G3: current repeatable full-workflow evidence across real project shapes; historical success and read-only results do not close this gap. |
| Recovery guidance for the complete workflow | [Migration safety](MigrationSafety.md#rollback-boundary), [interruption evidence](InterruptedMigrationValidation.md), [atomic tests](../Tests/PkgLiftMigrationTests/AtomicMigrationTests.swift) and [subprocess tests](../Tests/PkgLiftCLITests/MigrateInterruptionTests.swift) cover errors, handled signals, SIGKILL markers and refusal to reapply. | G4: a tested user recovery drill including the separate `pod install` and final-build boundary. Manual recovery may satisfy the gate. |
| Mature registry and contribution validation | 25 mappings in the verified 0.10.0 distribution; [contribution rules](ContributingMappings.md), duplicate registry copies, schema validation and [three Swift consumer pilots](VerifiedConsumerMappings.md). | G5: audit the evidence and published claims for the mappings included in the support contract; do not present a minimum version as proof of every later version. |
| Clear language boundaries | [Compatibility table](../README.md#compatibility), PBX source profiles and mapping-specific language refusal tests. Repository-owned SDWebImage fixture builds Swift and Objective-C consumers together. | G1/G3: publish a tested language/project-shape table with explicit detection-only and unsupported rows. |
| Partial and mixed-manager migrations | [Real-project procedure](RealWorldTesting.md), planner/preflight preservation checks and read-only mixed classifications. The current [mixed-language fixture](../Fixtures/MixedLanguageSDWebImage/Podfile) has only one pod; its [E2E runner](../Scripts/run-positive-e2e-pilot.sh) refreshes an empty Podfile after apply. | G3: build a migrated SwiftPM product alongside a retained non-AUTO CocoaPods dependency, with correct target linkage and dependency state. |
| No known critical migration-integrity defects | Protected CI and CodeQL passed for the baseline. Only [SwiftSoup #57](https://github.com/Alexsvensson99/PkgLift/issues/57) and [DGCharts #56](https://github.com/Alexsvensson99/PkgLift/issues/56) were open in the live issue inventory on 2026-09-16. | G5/G6: targeted safety review, triaged findings and exact-candidate checks. An empty defect tracker is not proof that no defects exist. |

The completed [0.10 publication](https://github.com/Alexsvensson99/PkgLift/actions/runs/35066745671)
and [Homebrew verification](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/35068498783)
establish a working distribution process. They cannot substitute for a future
1.0 candidate's artifact acceptance.

## Ordered work packages and exit criteria

### G1 — Define the 1.0 compatibility contract

**Priority: first. Status: implemented and locally verified on 2026-09-16.** The
[compatibility contract](Compatibility-1.0.md) and focused contract examples/tests
are implemented. Public integration and the remaining qualification gates are separate.

- Inventory public CLI commands/options/exit codes, JSON fields/reason codes,
  configuration and registry schemas, and the six exported library products
  plus the `pkglift` executable in [Package.swift](../Package.swift). State which Swift APIs are covered by the
  1.x source-compatibility promise; do not assume a CLI promise covers them all.
- Separate reading a report from executing a plan. Document additive-field and
  unknown-value handling, breaking-change policy, deprecation policy and the
  exact-version apply rule. Human prose is not a machine-readable contract.
- Prove current-plan round trips, supported older report decoding, refusal of
  unsupported schemas/versions and missing/stale AUTO evidence before writes.
  Extend the existing [preflight tests](../Tests/PkgLiftMigrationTests/MigrationPlanPreflightTests.swift)
  only for uncovered contract cases.
- Publish the support-table structure: host OS/architecture, Xcode build, Swift,
  CocoaPods, target platform/deployment, project/workspace shape and languages.
  Mark each row tested, pending or unsupported; do not fill unknown versions by inference.

**Exit:** every advertised public surface has a written compatibility rule and
corresponding evidence or a named remaining gate. No implicit cross-version
plan execution or newly automatic dependency is introduced.

### G2 — Qualify the declared environments

**Priority: second; depends on G1. Status: in progress.** The
[environment matrix and reproducible records](Environments-1.0.md) document
baseline evidence and the local Xcode 27 source/runtime checks. The registry
resource-layout compatibility fix passes both build engines. Hosted macOS
14.8.9/arm64 runtime smoke also passed. Exact 14.0 runtime evidence,
support-boundary decisions and complete consumer cells remain requirements below.

- Distinguish three promises: running the distributed CLI, building PkgLift from
  source, and migrating/building a consumer project. Record exact macOS, CPU,
  Xcode build, Swift and CocoaPods versions for each applicable cell.
- Check the distributed binary, bundled registry, quarantine/signature behavior
  and core workflow on the lowest promised host OS. For each supported source
  build cell, pass build/test/registry. For each migration toolchain cell, pass
  baseline and post-migration builds plus a representative partial-migration case.
- Select concrete lower and upper supported toolchains from available, tested
  environments; do not claim “all newer Xcode versions” from the single current cell.
- If a required environment is unavailable, leave the row pending. Narrowing an
  existing advertised support promise requires an explicit documented decision.
  Neither a skipped job nor a minimum deployment setting closes the gate.

**Exit:** no pending cells remain inside the proposed support envelope. Keep
existing protected checks; design additional runs around coverage, not duplicate
compilation. Do not trigger full workflows merely to estimate runtime.

### G3 — Prove real and partial migrations

**Priority: third; test design can proceed alongside G2 after G1. Status: in progress.**
The two [repository-owned partial-migration cases](PartialMigration-1.0.md#local-qualification-on-2026-09-16)
passed locally on Xcode 27 with fresh post-migration builds. Real-project, existing
SwiftPM coexistence and additional toolchain/shape evidence remain open.
Deliver an evidence matrix separating read-only, repository-fixture and real-project results.

- Preserve the ten upstream read-only pilots and their current prohibition on
  upstream apply/build. Review a separate, explicitly authorized protocol for
  disposable real-project copies or reproducible maintainer-provided reports.
  Source availability alone is not permission to run a project's scripts.
- Proposed minimum: three pinned real-project cases across at least two independent
  upstream repositories. Cover a supported Swift app, a partial migration with
  retained CocoaPods dependencies, and an explicit workspace/project or multi-target
  selection. Record positive and refusal coverage for every language/shape promised
  in G1; these three cases are a floor, not universal-compatibility proof.
- For each positive case: record upstream SHA and license, project/scheme and
  toolchain; pass the baseline build; review the exact AUTO set; prove dry run is
  inert; apply; refresh dependencies explicitly; verify structure and the final
  build; inspect the diff and preserve unrelated source/resources/settings.
- Qualify the [repository-owned partial-migration pilots](PartialMigration-1.0.md) for Swift-only and
  mixed Swift/Objective-C targets. At least one AUTO dependency must migrate and
  at least one non-AUTO dependency must remain. Prove both consumers still compile,
  the retained pod and CocoaPods integration survive refresh, and SwiftPM is linked
  exactly once to the intended target. Include existing SwiftPM coexistence and
  conflicting-requirement refusal in the coverage matrix.
- An unbuildable upstream baseline is inconclusive, not a migration success or
  regression. Select a suitable replacement or record a support blocker. Never
  edit classifications, simplify unsupported semantics or weaken checks to pass.

**Exit:** each promised workflow/shape has reproducible positive or intentional
refusal evidence. Reports identify source SHA, commands, artifact/binary identity,
environment, expected actions, remaining dependencies and redacted results.

### G4 — Verify recovery as a user procedure

**Priority: fourth; can proceed alongside G3. Status: open.** Deliver a recovery
runbook and executable drills on disposable, buildable fixtures.

- Reuse current error/signal tests and add only missing user-flow coverage for
  interruptions at Podfile and project/package-write boundaries, including SIGKILL.
- Prove automatic rollback where promised. For unhandled termination, prove
  fail-closed reapply refusal, preserved evidence and a manual restore procedure
  that restores verified originals and a working baseline before replanning.
- Exercise errors during subsequent `pod install` and `verify --build`. Explain
  that successful apply ends automatic rollback coverage. Restore the complete
  workflow baseline from a verified independent/VCS backup, including affected
  lockfile/workspace state; the internal Podfile/project backup is not a blanket
  snapshot of changes made by external tools.
- Keep the partial-backup and power-loss limits explicit. Retain recovery data
  until verification is complete. Do not claim universal crash/power-loss recovery.

**Exit:** another maintainer can follow the documented procedure and obtain the
expected restored build and refusal behavior. An automatic recovery command is
optional unless the drill demonstrates that the manual route is insufficient.

### G5 — Close safety and evidence findings

**Priority: before candidate freeze; depends on G1–G4 findings. Status: open.**

- Review migration-integrity paths: static parsing, target/platform/language
  attribution, path containment, saved-plan freshness, registry/product identity,
  partial-state preservation and write/rollback sequencing. Record each finding,
  severity, disposition and focused regression evidence.
- Audit registry contribution checks and mapping-specific support claims against
  their evidence. Fix unsupported claims or behavior rather than broadening AUTO.
- Require zero unresolved critical or high-severity findings affecting migration
  integrity or the declared support contract. Triage lower-severity findings with
  explicit rationale and tests; an unsupported input must remain a safe refusal.

**Exit:** support claims and evidence agree, safety findings have reviewable
dispositions, and no blocking correctness defect remains. This planning review
is not an exhaustive security audit and does not close this gate.

### G6 — Qualify and publish the exact 1.0 candidate

**Priority: last; depends on G1–G5. Status: open.**

- Freeze the candidate scope and version, document upgrade/plan regeneration,
  and pass the mandatory build, tests, registry, pilot and CodeQL checks on the
  reviewed PR and exact merged preparation commit.
- Test the signed/notarized candidate's installed-style workflow, including a
  supported migration, a partial migration and conservative refusal. Keep build
  verification evidence distinct from runtime functionality of third-party libraries.
- Follow the existing [distribution contract](Distribution.md): manifest-only
  source binding, private artifact acceptance, protected publication approval,
  public checksum/signature readback and Homebrew installation/test/uninstall.
  Repeat artifact acceptance on the actual manifest publication commit as required.
- Finish public release notes, support/recovery documentation and final live readback.

**Exit:** all six gates have dated, source-bound evidence and the approved release
is publicly verified. Prior approval of 0.10.0 publication is not 1.0 publication approval.

## Prioritization and version decision

With **G1 locally verified**, the next work package is G2's environment matrix;
G1 also determines G3's project selection. Perform G2–G4, integrate their fixes through G5 and
prepare G6. Use one reviewed tracking item and bounded issues for these work
packages when implementation is started; this local plan creates no GitHub issues
or milestone and triggers no CI or release workflow.

[SwiftSoup #57](https://github.com/Alexsvensson99/PkgLift/issues/57) and
[DGCharts #56](https://github.com/Alexsvensson99/PkgLift/issues/56) remain research
backlog, not mandatory 1.0 additions. Reprioritize only if a selected real-project
case establishes a concrete need and full mapping admission is independently met.

Do not schedule 0.11 by default. Proceed toward a 1.0 candidate if the gates can
be closed within the declared scope. Ship an intermediate 0.x only when a specific
fix or contract change warrants separate user validation. No date or 1.0-readiness
claim is made by completing this plan.

## Validation of the original planning change

The review inspected current source, tests, workflows, documented evidence and
live main/release/open-issue state. An independent read-only review covered pilot,
toolchain and recovery gaps. No new Swift build, pilot, consumer build, security
scan or artifact qualification was performed: these are future work packages.
Validate this documentation change by reviewing evidence claims, local links,
anchors and whitespace. Existing protected CI remains mandatory if submitted for merge.

## G1 implementation validation

The [compatibility contract](Compatibility-1.0.md#local-g1-validation) records
the CLI/JSON/library rules, six new regression/client tests, all 576 passing
Swift tests, successful build and validation of 25 registry mappings. An
independent source review checked the contract against implementation. The local
Xcode 27 build required the native build engine after a Swift Build signing
failure involving Finder metadata; this is not a qualified G2 support cell.
No public integration, consumer migration qualification or 1.0 publication is
claimed by this local result. G2–G6 remain open.
