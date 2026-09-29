# Adopted initial 1.0 support envelope

Status: **scope adopted on 2026-09-29; qualification remains open.** The decision
defers only the external positive multi-target/workspace cell from the initial
1.0 positive-qualification envelope. It does not change the CLI, registry,
classifications or release status. The G2 environment boundary is evidence-bound
as recorded below; its final-candidate runs, the non-deferred G3 rows and G4–G6
remain release gates. Registry eligibility remains unchanged; the [mapping evidence audit](RegistryEvidence-1.0.md) found no contradicted identity, product or minimum boundary requiring a restriction.

## Recorded decisions

On 2026-09-29, the initial 1.0 contract adopted deferral of an **external,
positive multi-target/workspace migration** from its positive-qualification
envelope. The deferred cell is explicit post-1.0 qualification work. It is not
renamed as complete, replaced by a repository fixture or satisfied by a safe
refusal. Existing CLI/API behavior is retained.

The same decision round selected Apple Silicon and an evidence-bound G2 matrix.
The supported runtime floor is the lowest macOS version on which the exact final
candidate passes runtime acceptance. The macOS 14.8.9 observation is historical
baseline evidence, not proof for the final candidate, and deployment metadata
does not establish exact 14.0 runtime support. Xcode 16.4/Swift 6.1.2 and Xcode
27/Swift 6.4 are separate selected cells; no version range between or after them
is inferred. Detailed workload rows and current-candidate results remain G2 work.

## Why the decision was needed

The current compatibility table keeps project/workspace/target breadth pending
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

| Area | Adopted initial 1.0 statement | Evidence boundary and remaining work |
|---|---|---|
| Public CLI and six library products | Retain the current 1.x compatibility policy, command/options meanings, report/plan distinctions and exact-version executable-plan preflight. | This is an interface promise, not a consumer-build or runtime claim. G6 still freezes the exact public API and candidate. |
| Static analysis and conservative outcomes | Retain the current literal parsing, project discovery, target attribution and typed REVIEW/BLOCKED/UNKNOWN outcomes. Unsupported constructs remain non-automatic. | A safe refusal is useful existing behavior; it is not a successful migration. No registry identity becomes AUTO through this adoption. |
| Repository-owned positive partial migrations | Include only the qualified `PartialSwift`, `PartialMixed` and `PartialSwiftCoexistence` fixture shapes: iOS 15, pinned dependencies, exact reviewed AUTO set, retained CocoaPods integration and fresh structural/post-migration builds. | These are controlled regression cells. They demonstrate Swift-only, Swift/Objective-C and existing-SwiftPM coexistence behavior only at their recorded inputs/toolchains. |
| External positive partial migration | Treat the pinned AWS Grid Feed result as historical external single-target partial-migration evidence, to be requalified against the exact 1.0 candidate if it is used in the release claim. | One historical external case cannot prove a current candidate, all Swift mappings or a target/workspace shape it does not contain. |
| External positive multi-target/workspace migration | **Deferred on 2026-09-29.** Do not make a positive external multi-target or workspace success claim in the initial envelope. | This specific G3 cell remains open post-1.0 work requiring a reviewed immutable intake, baseline, current-executable AUTO result, dry run, apply, CocoaPods refresh, preservation checks and final build. |
| Multi-target regression coverage | Retain repository target-attribution, sibling-preservation and mixed-language regression coverage. | Repository coverage is not substituted for an external qualification. It must be described as regression evidence, not as external project proof. |
| Languages and mappings | State support only per mapping, exact version, target, detected language and platform evidence. Swift and mixed Swift/Objective-C evidence is bounded to the named fixtures and mappings. | Do not claim that all Swift mappings, all Objective-C projects, or all versions matching a registry lower bound are positively qualified. Objective-C++, C and C++ remain detection/non-automatic without complete evidence. |
| Toolchains and hosts | Apple Silicon only. Set the supported runtime floor from the exact final candidate's lowest passing macOS host. Qualify selected Xcode 16.4/Swift 6.1.2 and Xcode 27/Swift 6.4 cells separately. | Historical macOS 14.8.9 does not qualify the final candidate or exact 14.0. Final workload rows and same-run evidence remain G2 work; no support continuum or “all newer Xcode” promise is implied. |
| Recovery and release | Keep G4 recovery drills, G5 safety/evidence disposition and G6 exact-candidate/artifact acceptance as required gates. | Deferring the external multi-target cell does not waive recovery, safety review, signing/notarization, distribution or release approval. |

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

## Adoption record and remaining acceptance criteria

The product-contract decision is recorded above; it is not release acceptance.
The remaining implementation and qualification criteria are:

1. A reviewed documentation change that preserves existing CLI/API
   behavior while accurately updating the plan, compatibility table and README;
   no existing support promise may disappear by implication.
2. A candidate evidence matrix that labels every row as qualified positive,
   qualified refusal, regression-only, historical-only, pending or deferred.
3. Completion of every G2 cell inside the finally advertised host/toolchain
   envelope, with exact same-run source, binary and environment evidence.
4. G3 remaining open until the adopted envelope's non-deferred positive and
   refusal rows have current-candidate evidence. The deferred external cell must
   remain visibly tracked for post-1.0 qualification.
5. Completion of G4, G5 and G6, including recovery drill, safety disposition and
   exact release-artifact acceptance, before 1.0 publication.

## Evidence consulted

- [Compatibility contract](Compatibility-1.0.md#support-table-and-qualification-state)
  distinguishes pending support rows from tested baselines and keeps external
  project/workspace breadth in G3.
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
