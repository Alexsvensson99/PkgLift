# Generated-Package Stage 1 Validation

Status: **locally implemented and verified on 2026-09-04; not published.**

Stage 1 implements the approved Option A from the
[generated-package evidence contract](GeneratedPackageEvidence.md). It produces
a structural blueprint candidate for one repository-owned synthetic Swift
library when the supplied evidence is complete, canonical and consistent with
the exact Podspec JSON bytes. Other inputs retain typed refusal reasons.

## Change boundary

The work starts from main commit
`5a1db0123cf2eb07076b8f736a813b5e29ea5314` on local branch
`codex/v0.6-stage1`. Commit `12b8a6b` first restores the original Stage 0 design.
Implementation was prepared in a separate local working copy; the original
checkout's existing changes were preserved.

Three new files in `PkgLiftCocoaPods` provide the evidence model, bounded JSON
entry points and pure assessor. The result preserves the original v0.5
assessment. Only the exact S1 source-selection reason can be discharged in the
separate blueprint result. The synthetic fixture's provenance and asserted
content are recorded in its
[README](../Tests/PkgLiftCocoaPodsTests/Fixtures/GeneratedPackageS1/README.md).

The v0.5 implementation and fixtures, migration-plan schemas, CLI, classifier,
planner, registry, verification and Xcode source, dependencies and workflows
have no changes relative to the base commit. The existing source-isolation
test now permits the three exact new analysis files alongside the original
assessment file, and forbids the `GeneratedPackage` prefix everywhere else
under `Sources`.

## Completed checks

| Check | Verified result |
| --- | --- |
| Debug `swift build` | Passed |
| Optimized `swift build -c release` | Passed |
| Full `swift test` | 423 passed: 271 XCTest and 152 Swift Testing tests |
| New S1 suite | 16 passed, included in the full run |
| `pkglift registry validate` | 22 mappings valid |
| `ruby Scripts/validate-repository-yaml.rb` | 14 YAML files, 10 SHA-pinned workflows and 2 issue forms valid |
| Release-manifest Python suite | 26 tests passed |
| Independent source and safety review | All identified findings resolved; no open findings |

The S1 tests exercise all four outcomes and all 25 reason codes, the 23 required
inventory groups, missing and contradictory evidence, exact byte bindings,
path and index boundaries, duplicate and unknown JSON fields, unsupported
profiles and shapes, deterministic encoding, privacy and source isolation.
Adversarial coverage includes direct-decoder bypass attempts, excessive source
counts and a retained v0.5 diagnostic set that exceeds the portable result's
budget. The assessor rejects oversized output before returning it.

Builds used four jobs with task-local SwiftPM and compiler caches. Thermal
checks permitted the work; no verification was deferred. A task-local runner
bounded `.build` to 1.5 GiB; its measured final size was approximately 999 MiB.
The user-level SwiftPM cache was unavailable in the sandbox, so validation used
the local cache paths instead.

Raw debug, optimized-build and test logs remain in the ignored
`.pkglift/validation/` directory of this working copy. The final full-suite log
is `full-tests-final.log`; the optimized-build and policy logs are
`release-build.log` and `release-policy.log`.

## Remaining gate

The next gate is review of the local diff for a pull request. No branch push,
pull request, tag, release or package publication was performed.

S1 remains an in-memory analysis API. Source existence, file contents and
provider claims are not independently verified. Package manifest generation,
compilation of a generated package, build/runtime equivalence and migration
integration require separate implementation and review.
