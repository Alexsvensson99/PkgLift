# Adopted initial 1.0 support envelope

Status: **scope adopted on 2026-09-29 and published with 1.0 on
2026-09-29.** The [final qualification](Qualification-1.0.md) records
acceptance inside this envelope. Only the external positive multi-target/workspace
cell is deferred post-1.0. The decision did not weaken classifications, registry
eligibility or migration safeguards. The [mapping audit](RegistryEvidence-1.0.md)
found no contradicted identity, product or minimum boundary requiring restriction.

## Recorded decisions

On 2026-09-29, the initial 1.0 contract adopted deferral of an **external,
positive multi-target/workspace migration** from its positive-qualification
envelope. The deferred cell is explicit post-1.0 qualification work. It is not
renamed as complete, replaced by a repository fixture or satisfied by a safe
refusal. Existing CLI/API behavior is retained.

The same decision round selected Apple Silicon and an evidence-bound G2 matrix.
The supported runtime floor is the lowest macOS version on which the exact final
candidate passes runtime acceptance. At that decision, the earlier 0.10 macOS
14.8.9 observation was historical baseline evidence, not proof for the final
candidate. Signed M subsequently passed its own macOS 14.8.9 runtime acceptance;
deployment metadata does not establish exact 14.0 runtime support. Xcode 16.4/Swift 6.1.2 and Xcode
27/Swift 6.4 are separate selected cells; no version range between or after them
is inferred. The [final environment matrix](Environments-1.0.md#final-10-evidence-matrix) records
the independent accepted workload rows.

## Why the decision was needed

At adoption, the compatibility table kept project/workspace/target breadth pending
until G3 and says that repository-owned fixtures do not qualify external
multi-target/workspace selection. The 2026-09-26 checkpoint likewise records
that PartialMixed is a repository-owned mixed-language partial-migration cell,
not an upstream multi-target project. ZBNetworking is now a REVIEW regression
case because its flat header import may depend on CocoaPods header-search-path
behavior; bounded inspection requires review without finding every flat import
inherently unsafe. Its earlier positive screen cannot close G3. The bounded
replacement intake found no external replacement satisfying
its static, locked, multi-target and non-dynamic requirements.

Those facts leave a real evidence gap. They do not establish that existing CLI
behavior is unsupported or that a mapping may be made AUTO less conservatively.
The compatibility contract already permits a safety correction to tighten AUTO
eligibility when new evidence identifies risk, and requires replanning; it does
not permit a silent widening of migration authority.

## Adopted envelope

This is the adopted **positive qualification envelope**, separate from retained
CLI behavior and from documented detection/refusal behavior.

| Area | Adopted initial 1.0 statement | Accepted evidence boundary |
|---|---|---|
| Public CLI and six library products | Retain the current 1.x compatibility policy, command/options meanings, report/plan distinctions and exact-version executable-plan preflight. | This is an interface promise, not a consumer-build or runtime claim. The [API baseline](API-1.0.md) and final M release freeze this surface. |
| Static analysis and conservative outcomes | Retain the current literal parsing, project discovery, target attribution and typed REVIEW/BLOCKED/UNKNOWN outcomes. Unsupported constructs remain non-automatic. | A safe refusal is useful existing behavior; it is not a successful migration. No registry identity becomes AUTO through this adoption. |
| Repository-owned positive partial migrations | Include only the qualified `PartialSwift`, `PartialMixed` and `PartialSwiftCoexistence` fixture shapes: iOS 15, pinned dependencies, exact reviewed AUTO set, retained CocoaPods integration and fresh structural/post-migration builds. | These are controlled regression cells. They demonstrate Swift-only, Swift/Objective-C and existing-SwiftPM coexistence behavior only at their recorded inputs/toolchains. |
| External positive partial migration | The pinned AWS Grid Feed partial migration/build passed on 1.0 source P in run 36606015426; unchanged production/registry/harness bytes bind the result through F and M. | This is named source qualification, not a signed M artifact execution. It does not qualify all mappings or an absent target/workspace shape; see the [source binding](Evidence/Qualification-1.0/source-qualification.json). |
| External positive multi-target/workspace migration | **Deferred on 2026-09-29.** Do not make a positive external multi-target or workspace success claim in the initial envelope. | This specific G3 cell remains open post-1.0 work requiring a reviewed immutable intake, baseline, current-executable AUTO result, dry run, apply, CocoaPods refresh, preservation checks and final build. |
| Multi-target regression coverage | Retain repository target-attribution, sibling-preservation and mixed-language regression coverage. | Repository coverage is not substituted for an external qualification. It must be described as regression evidence, not as external project proof. |
| Languages and mappings | State support only per mapping, exact version, target, detected language and platform evidence. Swift and mixed Swift/Objective-C evidence is bounded to the named fixtures and mappings. | Do not claim that all Swift mappings, all Objective-C projects, or all versions matching a registry lower bound are positively qualified. Objective-C++, C and C++ remain detection/non-automatic without complete evidence. |
| Toolchains and hosts | Apple Silicon only. Signed M runtime passed on macOS 14.8.9; signed consumer acceptance passed separately on macOS 15.7.9/Xcode 16.4 and local macOS 27.0/Xcode 27.0. | The final M macOS 14 result is distinct from historical 0.10 evidence. The local M cell includes core runtime and all four named consumer flows. [Same-run records](Environments-1.0.md#final-10-evidence-matrix) imply neither exact 14.0 nor a toolchain continuum. |
| Recovery and release | G4 source-bound recovery drills, G5 safety/evidence disposition and G6 exact signed-artifact acceptance passed within their recorded scopes. | Deferring the external multi-target cell does not waive recovery, safety review, signing/notarization, distribution or release approval. |

## Explicitly retained, but not newly positively qualified

The following remain part of the product's existing behavior or documented
boundary, without being evidence for the proposed positive envelope:

- Existing project/workspace discovery and explicit-selection handling.
- Refusal of dynamic Ruby, install hooks, `use_frameworks!`, inherited target
  mapping, external Git/local pods and unsupported managers.
- Read-only upstream pilots and intentional refusal controls.
- Existing plan/rollback safeguards and handled-signal behavior; these do not
  establish the G4 complete-workflow recovery drill.
- Registry entries that are eligible only when their live mapping, version,
  language, platform, target and source evidence is complete.

## What the deferred G3 cell would require

The deferred external positive multi-target/workspace cell remains a concrete
post-1.0 work item, not an abstract aspiration. Before execution it requires a
licensed immutable upstream source, committed literal Podfile and lockfile, at
least two native targets, a static non-framework/non-hook model, complete source
import review, an exact current AUTO set and a buildable baseline. A separate
reviewed execution protocol must bind the source, PkgLift binary, toolchain,
target inventory, generated CocoaPods preparation, preservation scope and
redacted receipts. Success requires an inert dry run, apply, explicit dependency
refresh, structural/preservation checks and fresh final build. Runtime behavior,
signing and test execution remain distinct claims.

A repository-owned multi-target regression can improve confidence in classifier
and editor behavior, but cannot supply the upstream source ownership, generated
integration, baseline or preservation evidence required by that external cell.

## Adoption and release acceptance record

The adopted decision preserves existing CLI/API behavior while bounding positive
qualification. The [final record](Qualification-1.0.md) separates positive
results, refusals, historical source evidence and the deferred external cell.

- G2: signed M macOS 14.8.9 runtime; macOS 15.7.9/Xcode 16.4 signed consumer
  acceptance; local macOS 27.0/Xcode 27 signed runtime and four-consumer acceptance.
- G3: the three partial/coexistence fixtures, complete mixed migration/build,
  source-bound AWS partial migration and named FirebaseUI/Hammerspoon refusals.
  The external positive multi-target/workspace case remains deferred.
- G4: [eleven source-bound recovery drills](Recovery-1.0.md#candidate-source-rerun-on-2026-09-29),
  retaining the original paired CLI/test artifacts and unchanged-input binding.
- G5: [targeted safety dispositions](SafetyReview-1.0.md),
  [25-mapping audit](RegistryEvidence-1.0.md) and [public API baseline](API-1.0.md).
- G6: [exact M cloud acceptance](Evidence/Qualification-1.0/cloud-final-M-acceptance.json), [local M acceptance](Evidence/Qualification-1.0/local-final-M-acceptance.json),
  protected publication and [public/Homebrew readback](Evidence/Qualification-1.0/public-distribution.json).

These results do not turn detection, a refusal or fixture regression into
external positive multi-target/workspace qualification. The deferred protocol
above remains the post-1.0 acceptance requirement.

## Evidence consulted

- [Compatibility contract](Compatibility-1.0.md#support-table-and-qualification-state)
  distinguishes qualified workload rows, historical baselines and the deferred
  external positive multi-target/workspace cell.
- [Plan 1.0](Plan-1.0.md#g3--prove-real-and-partial-migrations) requires real
  project-shape evidence and says fixtures do not close those shapes.
- [Partial migration qualification](PartialMigration-1.0.md#main-qualification-on-2026-09-16)
  qualifies three repository-owned fixtures and explicitly excludes external
  multi-target/workspace selection.
- [Qualification checkpoint](Qualification-2026-09-26.md#g3-disposition) records
  the ZB REVIEW correction, open replacement requirement and unresolved G2/G3/G4
  gates.
- [Replacement intake](G3-Replacement-Intake-2026-09-26.md) records the bounded
  authorized public search and its lack of a qualifying external replacement.
