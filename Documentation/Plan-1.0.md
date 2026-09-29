# PkgLift 1.0 plan: a verified support and compatibility contract

Status: **1.0 published on 2026-09-29 within the adopted scope.**
Final source F is `1839cbfe614c3affeecd6c790bb43ca2053a334a`; manifest-only M is
`207ff4e92b2fc4ed39c5fd8a4c2270eb0093faf9`. [Final qualification](Qualification-1.0.md),
[public Release](https://github.com/Alexsvensson99/PkgLift/releases/tag/v1.0.0) and [Homebrew readback](Evidence/Qualification-1.0/public-distribution.json)
record G1–G6 completion within the envelope. The external positive
multi-target/workspace cell remains explicitly deferred post-1.0.

## Completion record

| Gate | Dated outcome and evidence |
| --- | --- |
| G1 | Public CLI/JSON/config/registry/library rules and the 1,931-symbol API baseline are frozen for 1.0. [Compatibility](Compatibility-1.0.md), [API](API-1.0.md). |
| G2 | Signed M macOS 14.8.9 core runtime, hosted Xcode 16.4 consumer acceptance and independent local Xcode 27 signed runtime/four-consumer acceptance passed on 2026-09-29. [Environment matrix](Environments-1.0.md#final-10-evidence-matrix). |
| G3 | Named repository-owned flows and source-bound AWS/FirebaseUI/Hammerspoon cases passed. Only the external positive multi-target/workspace case is deferred. [Qualification](Qualification-1.0.md#final-protected-and-public-qualification). |
| G4 | All 11 candidate-source recovery scenarios and 97 commands passed on 2026-09-29; the original paired-artifact/build-input identities are preserved and bound through F/M. [Recovery](Recovery-1.0.md#candidate-source-rerun-on-2026-09-29). |
| G5 | Targeted review has no confirmed unresolved critical/high migration-integrity finding; the public caller precondition is documented, 25 mapping claims audited and the API baseline captured. [Safety](SafetyReview-1.0.md), [registry](RegistryEvidence-1.0.md), [API](API-1.0.md). |
| G6 | Exact M cloud and local acceptance preceded protected publication; public tag/checksum/binary and the Homebrew PR lifecycle were separately verified; Homebrew main CI passed. [Release notes](ReleaseNotes-1.0.0.md), [distribution readback](Evidence/Qualification-1.0/public-distribution.json). |

The original plan was reviewed on 2026-09-16 against main `72f19b3…` and public
0.10.0. Its baseline gap tables and original acceptance criteria below remain
historical context. The [2026-09-26 checkpoint](Qualification-2026-09-26.md)
records why the former ZBNetworking positive screen became a REVIEW case; that
superseded screen is not positive 1.0 evidence. The [adopted scope](ScopeProposal-1.0.md)
defers the missing external positive cell without weakening safety or renaming
refusals as successes.

## Outcome and scope

Make the existing Analyze → Plan → dry run → Apply → Verify workflow dependable
within an explicit, tested support envelope. A successful partial migration must
preserve dependencies that still need CocoaPods. Unsupported inputs must retain
their conservative classifications and useful explanations.

The [roadmap quality bar](../ROADMAP.md#v10--production-grade-cocoapods-modernization) remains the release standard.
The first work package is the support/compatibility contract below, followed by
evidence for each promised workflow. Adding more registry identities is not a
substitute for these gates.

Adopted boundaries for this plan:

- Retain Apple Silicon distribution. Set the supported runtime floor to the
  lowest macOS version on which the exact final candidate passes runtime
  acceptance. Signed M subsequently passed macOS 14.8.9 independently of the
  earlier 0.10 baseline; exact 14.0 support must not be inferred from deployment
  metadata.
- Qualify the selected Xcode 16.4/Swift 6.1.2 and Xcode 27/Swift 6.4 cells as
  distinct cells. Do not infer support for toolchains between or after them, and
  do not treat a source-build result as consumer-migration evidence.
- Preserve exact mapping, target, language, platform, version and live-preflight
  requirements. Swift, Objective-C and mixed targets remain mapping-dependent.
  Detection of Objective-C++, C or C++ does not imply automatic migration support.
- Retain the exact PkgLift-version requirement for executing saved plans. An
  upgrade requires regeneration even when the JSON schema remains readable.
  Cross-version apply is not a prerequisite for 1.0.
- Keep generated-package APIs and local source-inspection reports separate from
  migration authority. No new package generation, Ruby execution, external-source
  migration, platform expansion or automatic recovery command is included by default.

## Historical evidence and gaps at the baseline

“Established” below means a baseline capability or recorded result, not fresh
qualification of a future 1.0 binary. “Gap” means missing coverage or an unresolved
support promise, not a demonstrated implementation defect.

| Roadmap requirement | Established evidence | Remaining 1.0 gate |
|---|---|---|
| Stable plan schema or explicit compatibility policy | [JSON contracts](JSONSchema.md): analysis and verification schema 1; migration plans schema 1/2 according to their registry evidence. Additive inspection compatibility, schema/evidence pairing and exact `pkgLiftVersion` equality are enforced by [preflight](../Sources/PkgLiftMigration/MigrationPlanPreflight.swift). Older incomplete AUTO entries are refused. The [versioned compatibility policy](Compatibility-1.0.md) and focused examples/tests were integrated by PR #119 and qualified on main `9d2951…`. | G6 must freeze the exact release API baseline. |
| Supported host/toolchain matrix | [Ordinary CI](../.github/workflows/positive-e2e.yml), [CodeQL](../.github/workflows/codeql.yml) and [release CI](../.github/workflows/release.yml) use macOS 15 with Xcode 16.4. [Distribution](Distribution.md) advertises arm64 macOS 14+. | G2: set the supported Apple Silicon runtime floor from the exact final candidate's lowest passing host and qualify the selected Xcode 16.4 and Xcode 27 cells separately. Historical 14.8.9 does not prove the candidate or exact 14.0; no toolchain range is implied. |
| Broad real-project coverage | [Ten pinned upstream pilots](Pilots.md) exercise analysis, planning, inert dry run and conservative outcomes. Amazon IVS full migration is historical v0.2.0 evidence. Current recurring full apply/build runs use repository-owned fixtures. | G3: obtain current-candidate evidence for every non-deferred promised shape. The external positive multi-target/workspace cell is explicitly deferred post-1.0; historical success, fixtures and refusals do not convert it into a positive result. |
| Recovery guidance for the complete workflow | [Migration safety](MigrationSafety.md#rollback-boundary), [interruption evidence](InterruptedMigrationValidation.md), [atomic tests](../Tests/PkgLiftMigrationTests/AtomicMigrationTests.swift) and [subprocess tests](../Tests/PkgLiftCLITests/MigrateInterruptionTests.swift) cover errors, handled signals, SIGKILL markers and refusal to reapply. | G4: a tested user recovery drill including the separate `pod install` and final-build boundary. Manual recovery may satisfy the gate. |
| Mature registry and contribution validation | 25 mappings in the verified 0.10.0 distribution; [contribution rules](ContributingMappings.md), duplicate registry copies, schema validation and [three Swift consumer pilots](VerifiedConsumerMappings.md). | G5: audit the evidence and published claims for the mappings included in the support contract; do not present a minimum version as proof of every later version. |
| Clear language boundaries | [Compatibility table](../README.md#compatibility), PBX source profiles and mapping-specific language refusal tests. Repository-owned SDWebImage fixture builds Swift and Objective-C consumers together. | G1/G3: publish a tested language/project-shape table with explicit detection-only and unsupported rows. |
| Partial and mixed-manager migrations | On main `72f19b3…`, [PartialSwift, PartialMixed and PartialSwiftCoexistence](PartialMigration-1.0.md#main-qualification-on-2026-09-16) passed their baseline/post-migration builds, retained-pod refresh/lock checks and structural verification under macOS 15.7.9/arm64, Xcode 16.4, Swift 6.1.2 and CocoaPods 1.17.0. The [build/pilot](https://github.com/Alexsvensson99/PkgLift/actions/runs/35128107267), [Quality](https://github.com/Alexsvensson99/PkgLift/actions/runs/35128107306) and [CodeQL](https://github.com/Alexsvensson99/PkgLift/actions/runs/35128107438) runs contain 25 completed, successful checks in total. | G3: requalify the non-deferred partial/refusal rows and planned [pinned real-project cases](RealProjectQualification-1.0.md) against the candidate. Repository multi-target regressions remain regression evidence; external positive multi-target/workspace proof is deferred, not closed. |
| No known critical migration-integrity defects | Protected CI and CodeQL passed for the baseline. Only [SwiftSoup #57](https://github.com/Alexsvensson99/PkgLift/issues/57) and [DGCharts #56](https://github.com/Alexsvensson99/PkgLift/issues/56) were open in the live issue inventory on 2026-09-16. | G5/G6: targeted safety review, triaged findings and exact-candidate checks. An empty defect tracker is not proof that no defects exist. |

The completed [0.10 publication](https://github.com/Alexsvensson99/PkgLift/actions/runs/35066745671)
and [Homebrew verification](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/35068498783)
establish a working distribution process. They cannot substitute for a future
1.0 candidate's artifact acceptance.

## Ordered work packages and exit criteria

### G1 — Define the 1.0 compatibility contract

**Priority: first. Status: implemented and main-qualified on 2026-09-16.** The
[compatibility contract](Compatibility-1.0.md) and focused contract examples/tests
were integrated by PR #119 and qualified on main `9d2951…`. The remaining
release qualification gates are separate.

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

**Status: completed for the adopted 1.0 cells on 2026-09-29.** The
[final environment matrix](Environments-1.0.md#final-10-evidence-matrix) binds
signed M runtime at macOS 14.8.9 and the independent Xcode 16.4/27 consumer cells.
Historical observations and deployment metadata are not substituted for them.
The original acceptance criteria remain below.

- Distinguish three promises: running the distributed CLI, building PkgLift from
  source, and migrating/building a consumer project. Record exact macOS, CPU,
  Xcode build, Swift and CocoaPods versions for each applicable cell.
- Check the distributed binary, bundled registry, quarantine/signature behavior
  and core workflow on the lowest promised host OS. For each supported source
  build cell, pass build/test/registry. For each migration toolchain cell, pass
  baseline and post-migration builds plus a representative partial-migration case.
- Qualify Xcode 16.4/Swift 6.1.2 and Xcode 27/Swift 6.4 as separate selected
  cells for the workloads assigned to them in the final matrix. Do not claim a
  continuous range, every Swift 6 toolchain or “all newer Xcode versions.”
- If a required environment is unavailable, leave the row pending. Narrowing an
  existing advertised support promise requires an explicit documented decision.
  Neither a skipped job nor a minimum deployment setting closes the gate.

**Exit:** no pending cells remain inside the proposed support envelope. Keep
existing protected checks; design additional runs around coverage, not duplicate
compilation. Do not trigger full workflows merely to estimate runtime.

### G3 — Prove real and partial migrations

**Status: completed for non-deferred 1.0 rows; external positive multi-target/workspace qualification remains deferred.**
[Final qualification](Qualification-1.0.md#final-protected-and-public-qualification)
records source-bound AWS migration/build and FirebaseUI/Hammerspoon refusals on
P, all named repository-owned partial/coexistence cases on F, and separate signed
M cloud/local acceptance. Unchanged production/registry/harness bytes bind P/F/M;
the real-project run is not relabeled as a signed M execution. ZBNetworking
remains a REVIEW case, and no refusal or fixture replaces the deferred cell.
The original acceptance criteria remain below.

- Preserve the ten upstream read-only pilots and their current prohibition on
  upstream apply/build. Review a separate, explicitly authorized protocol for
  disposable real-project copies or reproducible maintainer-provided reports.
  Source availability alone is not permission to run a project's scripts.
- Initial 1.0 minimum: retain the three pinned real-project cases across three
  independent upstream repositories: the AWS positive partial migration and the
  FirebaseUI/Hammerspoon intentional refusal controls. Requalify any result used
  in the candidate claim. These cases are not universal-compatibility proof, and
  the refusal controls do not substitute for the deferred external positive
  multi-target/workspace cell.
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
  regression. Replace a non-deferred positive case or record its support blocker;
  do not restart an unbounded search for the deferred external multi-target cell.
  Never edit classifications, simplify unsupported semantics or weaken checks to pass.

**Exit:** each non-deferred promised workflow/shape has reproducible
current-candidate positive or intentional-refusal evidence. Reports identify
source SHA, commands, artifact/binary identity, environment, expected actions,
remaining dependencies and redacted results. The external positive
multi-target/workspace cell remains visibly deferred with its post-1.0 protocol;
fixture regressions and safe refusals are never counted as its positive evidence.

### G4 — Verify recovery as a user procedure

**Status: completed as source-bound recovery qualification on 2026-09-29.**
The [recovery runbook and executable drill](Recovery-1.0.md) exercise eleven
controlled scenarios on the repository-owned PartialSwift consumer. All restored
copies built and passed fresh planning/dry-run checks on 2026-09-26. This local
execution and independent review are separate from protected integration and
release-candidate acceptance.

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

**Status: completed; targeted review, registry claim audit and API baseline integrated in the final source.**

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
dispositions, and no blocking correctness defect remains. The [targeted review and dispositions](SafetyReview-1.0.md) close this scoped
gate; they are not an exhaustive security audit or proof that no defects exist.

### G6 — Qualify and publish the exact 1.0 candidate

**Status: public release verified on 2026-09-29 after exact signed M cloud/local acceptance; Homebrew main CI passed.**

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
is publicly verified. The 2026-09-29 standing 1.0 delivery mandate supplies
operator authorization; all technical gates and protected-environment approvals
still apply.

## Current work direction

Maintain the shipped 1.x compatibility and safety boundaries. The next unmet
qualification item is the [explicit deferred external positive multi-target/workspace protocol](ScopeProposal-1.0.md#what-the-deferred-g3-cell-would-require).
It requires a reviewed replacement source and complete positive evidence; it
must not be closed by rerunning the ZBNetworking refusal or by a repository fixture.
The [0.11 proposal](ReleaseProposal-0.11.md) remains a historical preparation
record; its safety changes shipped within 1.0.

## Historical prioritization and version decision

With **G1 merged and main-qualified**, the next work package is G2 candidate
qualification in the selected exact environment cells. The repository-owned G3
partial pilots and conflict-refusal coverage are also main-qualified; the
non-deferred real-project protocol determines the remaining initial G3 evidence,
while external positive multi-target/workspace qualification is tracked post-1.0.
Perform G2–G4, integrate their fixes through G5 and
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
claimed by this local result. PR #120 subsequently supplied main qualification
for G1, all three repository-owned G3 partial pilots and conflict-refusal coverage;
the planned real-project protocol and remaining gates were open at that
historical checkpoint. Their 1.0 disposition is recorded at the top of this document.
