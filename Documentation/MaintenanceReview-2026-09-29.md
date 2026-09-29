# Post-release maintenance review — 2026-09-29

The first-pilot guide is prepared locally. **Hold XcodeProj PR #133:** the
candidate reproduces an unintended project-format conversion. CodeQL PR #134
has no identified defect in the reviewed patch, but needs current-base checks
before merge. This review did not merge either PR, publish documentation,
contact pilot users, or start a remote workflow.

## Reviewed identities

| Item | Immutable identity | Result |
| --- | --- | --- |
| Current source baseline | `abb0df9aa7319affdbfc3677fa96519d8a339a29` | Published 1.0 documentation baseline |
| [PR #133](https://github.com/Alexsvensson99/PkgLift/pull/133) | `9678d04a66b4db3369f7c3aeb118fac647c4d205`, based on `4ff7b32dce8d706153ad682aa2332d0e61993738` | Hold for reproduced format defect |
| [PR #134](https://github.com/Alexsvensson99/PkgLift/pull/134) | `b5fd443d8e5835a4e30cf128193fea4ca9d6ae05`, based on `1839cbfe614c3affeecd6c790bb43ca2053a334a` | Patch acceptable for subsequent integration checks |
| Released 1.0 executable | SHA-256 `4e7997c6a03e19cf41d6413d90066dd17064f2975feddd066d5ef606556f998b` | Used for guide smoke and format-refusal comparison |

The local dependency experiment applied only PR #133's `Package.resolved` diff
to the current baseline. It was not an exact checkout of the older PR head.
The candidate pin and binary hashes, test totals, and raw-log hashes are in the
[review receipt](Evidence/Postrelease-2026-09-29/maintenance-review.json).
Local host: Apple Silicon, macOS 27.0 (26A428), Xcode 27.0 / Swift 6.4.

## P1 — XcodeProj upgrade can create two project definitions

[The upstream 9.16.0–9.17.5 change](https://github.com/tuist/XcodeProj/compare/9.16.0...9.17.5)
adds experimental `project.xcproj` JSON reading and writing. It also adds
`apple/xcode-project-format` 0.1.0, whose manifest requires Swift tools 6.1.
PkgLift's qualified Xcode 16.4 / Swift 6.1.2 cell meets that requirement;
this review does not establish additional toolchain support.

The new upstream reader accepts an `.xcodeproj` containing only `project.xcproj`.
PkgLift's analyzer and migration preflight do not reject that format. Its
[Xcode editor](../Sources/PkgLiftXcode/XcodeProjectEditor.swift) deliberately
calls `writePBXProj` to preserve unrelated workspace and scheme data. With the
new reader, that writer can create `project.pbxproj` beside the original JSON
project. Upstream then prefers the PBX file on subsequent reads.

The focused reproduction used the repository-owned `PartialSwift` fixture:

1. Convert the fixture into a fresh JSON-only project using the upstream writer.
   Record truthful explicit `sourcecode.swift` types for its two existing Swift
   source members. Registry mappings and PkgLift safety rules remain unchanged.
2. Generate a real plan: KeychainAccess `AUTO`, SDWebImage `BLOCKED` by the
   fixture's existing deny policy.
3. Apply in a clean disposable Git repository, ignoring only the generated
   plan. No `--allow-dirty` or edited plan was used.
4. Apply exits successfully and removes KeychainAccess from the Podfile, but
   creates `project.pbxproj` containing the new package/product while leaving
   the original `project.xcproj` bytes unchanged. The assertion prohibiting a
   second project definition fails.

The implicit-type variant safely produces `REVIEW` and no AUTO; the upstream
converter omits inferred PBX file types, and PkgLift correctly rejects the
incomplete language evidence. The initial probe stopped at that precondition.
Only the subsequent valid explicit-type variant reproduces the apply defect.
The signed released 1.0 binary refuses the same explicit JSON-only baseline
before planning with exit 1, without changing its inputs.

This proves unintended format conversion in the dependency candidate. It does
not prove data loss, how Xcode chooses between both files, or consumer build
behavior. No consumer build or external positive multi-target pilot was run.

**Required before integration:** prefer an explicit refusal of unsupported
project formats before analysis can authorize AUTO and before a mutation can
write. Retain the current 1.0 support boundary. Add a permanent regression that
covers JSON-only inputs with both implicit and explicit source types, clean
Git apply, unchanged original bytes, and absence of a second project file.
Broader format-preserving migration would be a separate feature decision.

The [temporary reproducer](Evidence/Postrelease-2026-09-29/PostreleaseXCProjProbeTests.swift.txt)
is preserved as text, outside the compiled test target. To reproduce, use an
isolated checkout of the baseline plus PR #133's exact lockfile diff, install
that file temporarily in `Tests/PkgLiftCLITests`, set `POSTRELEASE_PROBE_ROOT`
to a new existing artifact directory, and run `swift test --filter
PostreleaseXCProjProbeTests`. Follow local storage and thermal rules for
scratch/cache/TMPDIR paths. The explicit-format assertion is expected to fail
on the reviewed candidate. Do not include the temporary probe in a release.

## CodeQL PR #134

Both init and analyze change from 4.38.0 to 4.38.2 at the same full commit pin,
`2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2`. No trigger, permission, runner,
build mode, query suite, or gate logic changes. The upstream annotated 4.38.2
tag resolves to this commit; the tag itself is unsigned.

[4.38.1](https://github.com/github/codeql-action/releases/tag/v4.38.1) introduces
experimental per-language bundle support;
[4.38.2](https://github.com/github/codeql-action/releases/tag/v4.38.2) selects
CodeQL bundle 2.27.1. This is a runtime action update, not only a version comment.
The existing [PR CodeQL run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36611186473)
ran the exact new pin and CLI 2.27.1 for Swift successfully. The exact two-line
patch also passed the repository YAML/pinning validator locally and was then
restored byte for byte.

Both PRs have 26 successful existing checks but GitHub reports them behind
current main. Strict branch protection requires current-base checks: `build`,
`test`, `repository`, `Registry Gate`, `Pinned Pilot Gate`,
`Mixed-Language Pilot Gate`, and `CodeQL`. Update the selected PR branch, review
its resulting exact diff/head, and complete required checks before merge.
Existing green checks are not approval to bypass branch protection. No new
Actions minutes were used for this review.

## Pilot guide and validation

[Your first PkgLift 1.0 pilot](FirstPilot.md) stops at dry run, includes a small
feedback template, and links to the established apply/build procedure. README,
Support and the existing pilot document link to it. The existing report form
now records where the user stopped and permits truthful installation-failure
reports without an installed PkgLift version or prior project test.

The guide commands were exercised using the exact signed 1.0 binary on a fresh
copy of `PartialSwift`: version, registry validation, analyze, plan, dry run,
working-tree and staged diff checks. All nine original fixture files remained
byte-identical; only the generated plan appeared as untracked state. This is
a documentation smoke check, not a new external pilot or installation claim.
Local Homebrew installation was not retried; its earlier Command Line Tools
prerequisite limitation remains separate from the successful release CI.

Other completed checks: the current source plus dependency candidate built and
passed all 646 existing Swift tests (413 XCTest, 233 Swift Testing), and all 25
registry mappings validated. The two scenario probes then distinguished safe
implicit-type refusal from the explicit-type apply defect. Repository YAML,
issue-form structure, changed-document links and patch whitespace were checked.
The final local changes contain documentation, a feedback-form update and review
evidence only; the dependency lockfile, runtime sources, compiled tests and
workflows are restored to the source baseline.

Next bounded work is to implement and verify the format refusal, then reassess
PR #133. CodeQL can proceed independently through its required current-base
checks. The guide is ready for publication review; three real project reports
remain a proposed pilot target, not an achieved result.
