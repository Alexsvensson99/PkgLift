# PkgLift qualification checkpoint — 2026-09-26

Status updated 2026-09-27: local source, PartialMixed and eleven G4 recovery
scenarios passed. PR #135 subsequently passed ordinary CI with same-job
environment receipts. G2/G3 remain open; the focused G5 review has a bounded
follow-up and G6 candidate acceptance remains outstanding. No support boundary,
product version or public release was changed by this checkpoint.

Source baseline: `cbff61f47ebd7034509123afcc0afe0a831a009c` (PR #132), tree
`21af065373fc27c000ea7c1fedc8ea6e121d35a3`. Work used a separate clean checkout;
the older local growth-sprint branch and its uncommitted changes were preserved.
The latest public release checked on this date is [0.10.0](https://github.com/Alexsvensson99/PkgLift/releases/tag/v0.10.0).

## Completed local evidence

The [environment record](Evidence/Environments-1.0/local-2026-09-26-environment.json)
binds macOS 27.0 (26A428), arm64, Xcode 27.0 (27A266a), Swift 6.4
(`swiftlang-6.4.0.34.1`, clang `2100.3.34.1`), CocoaPods 1.17.0, macOS SDK
27.0 (26A425), and iOS Simulator SDK 27.0 (24A430).

The [validation receipt](Evidence/Environments-1.0/local-2026-09-26-validation.json)
records command exits and log hashes for:

- Debug build with the default Swift Build engine: passed.
- Full tests: 403 XCTest and 233 Swift Testing tests passed.
- Registry validation: all 25 mappings passed.
- Python release/harness policy tests: all 264 passed.
- Repository YAML validation: 13 files, nine pinned workflows and two issue forms passed.
- Complete repository-owned PartialMixed migration: passed.

The source build was outside the synchronized Documents checkout. Standard Swift
Build compiled and signed its test bundles successfully; no metadata stripping or
native-engine fallback was used. Build/cache/temp/log data were routed to the
verified external APFS SSD. The original source checkout remained unchanged.
These are local observations of this exact source, not acceptance of a signed
release binary or all newer Xcode/macOS versions.

The [PartialMixed summary](Evidence/Environments-1.0/local-2026-09-26-PartialMixed-summary.json)
and [same-run environment](Evidence/Environments-1.0/local-2026-09-26-PartialMixed-environment.json)
prove baseline and fresh post-migration builds, one exact SDWebImage 5.18.1 AUTO
action, inert dry run, retained KeychainAccess 4.2.2/CocoaPods integration, exact
SwiftPM linkage and revision, and preserved consumer sources/resources/settings.
The builds used Debug, arm64 iOS Simulator, iOS deployment 15.0 and disabled code
signing. The baseline and final builds used separate DerivedData directories.
No app or simulator was launched. This qualifies one repository-owned mixed
Swift/Objective-C partial-migration cell, not an upstream multi-target project.

## G2 gap register and next evidence

The three promises below must remain separate: distributed CLI runtime, building
PkgLift from source, and migrating/building a consumer. No support row changes
from pending to supported merely because its metadata is known.

| Cell / decision | Current evidence | Required next evidence |
|---|---|---|
| Lowest advertised CLI host, macOS 14.0 arm64 | Signed 0.10.0 ran on 14.8.9; exact 14.0 is unavailable in the inspected local environment. | Execute the exact candidate on 14.0, or obtain a separately documented support-boundary decision. Preserve the current advertised minimum meanwhile. |
| Hosted source, macOS 15 / Xcode 16.4 | Historical protected builds/tests pass; older retained source records omit exact compiler/Xcode fields. | Save complete environment and runner-image metadata in the same normal protected source-build job as its exact source/result. Do not infer missing values from adjacent jobs. |
| Local source, macOS 27 / Xcode 27 | Current-main standard-engine build, full tests and registry passed in this checkpoint. | Explicitly select the source-support envelope, then requalify the final candidate. This local cell alone does not establish a range of Xcode versions. |
| Local mixed partial consumer, Xcode 27 | Current-main PartialMixed complete workflow passed with same-run environment metadata. | Retain this exact cell; qualify other promised shapes separately and repeat candidate acceptance where required. |
| Other hosted consumer cells | KeychainAccess, DeviceKit, CryptoSwift and mixed SDWebImage have build evidence; older records omit parts of host/CPU/compiler metadata. | Capture complete same-job metadata with the next normal qualifying run, retaining source, binary, dependency and result identities. |
| Hosted partial/coexistence fixtures | PartialSwift, PartialMixed and PartialSwiftCoexistence all passed on main `72f19b3…` with complete metadata. | Do not list coexistence as still missing in the historical fixture matrix; new toolchains and final artifacts still need their own checks. |
| Exact lower/upper supported source and consumer toolchains | Xcode 16.4 hosted and Xcode 27 local observations exist. | Record an explicit proposed envelope, then close every advertised cell. Do not claim all versions between or after the observed cells. |

No extra hosted workflow was dispatched for this checkpoint. The next CI evidence
should be collected in required normal checks, preserving shared compilation and
all protected gates. The local workflow change adds source-build environment capture plus a separate
14-day artifact, and adds environment JSON to the existing mixed and registry
consumer reports. It adds no job or compilation. `capture-environment.py` records
bounded `ImageOS` and `ImageVersion` values only on GitHub Actions; missing image
metadata keeps the capture incomplete, and unsafe/unbounded values are omitted.
New local captures emit `runnerImage: null`; the clean-main receipts retained
here predate the added field and are preserved unchanged. This uses the runner variables described
by [GitHub runner-images](https://github.com/actions/runner-images/discussions/7661).
Four new tests cover same-capture image binding, missing image data, unsafe text
and local isolation. This is prepared instrumentation; its future hosted results
must still be read back before any G2 hosted cell is closed.

After the instrumentation change, all **268** Python policy tests passed, including
all seven environment-capture tests. YAML validation and an independent review
also passed. The [instrumentation validation receipt](Evidence/Environments-1.0/local-2026-09-26-instrumentation-validation.json)
binds the changed executable inputs by digest; the 636 Swift tests and full
PartialMixed run above belong to the unchanged product source at the clean-main
baseline. No product source changed in this checkpoint.

## G3 disposition

ZBNetworking is now an intentional refusal case: the consumer's flat header import
cannot be assumed to survive migration. The final section of the
[multi-target record](MultiTargetQualification-1.0.md#diagnosed-consumer-header-import-blocker)
supersedes its historical positive-AUTO screening. Re-running the old positive
protocol cannot close G3.

A replacement must have a pinned licensed source, a locked static dependency
model, at least two real native targets, an exact current AUTO set, a buildable
baseline and complete reviewed execution inputs. Missing generated CocoaPods
configuration may be resolved only by a separately reviewed preparation step; it
is not evidence of safe automatic migration by itself. Review the dependency
specifications and generated build phases before executing upstream code.

The existing AWS positive and FirebaseUI/Hammerspoon refusal results remain
historical coverage. No new external positive migration or completed G3 gate is
claimed here. The [replacement search record](G3-Replacement-Intake-2026-09-26.md)
records the bounded public candidate screen and its exclusions.

## Maintenance-release assessment

Recommendation: prepare a separately reviewed pre-1.0 **0.11.0** maintenance
candidate for the demonstrated header-import safety correction, rather than wait
for all 1.0 environments and project shapes. This is a proposed version and scope,
not a version bump, release-ready declaration or publication approval.

PR #132 corrects a reproduced failure where the CocoaPods baseline built but the
migrated consumer could not resolve `SDImageCache.h`. The fix conservatively
refuses affected targets and rechecks evidence before writes. Its `clear` result
is a bounded risk check, not compilation proof. Release notes must explain the
narrower AUTO eligibility, new reason values, incomplete-evidence refusals and
required regeneration of saved plans.

At the recorded main baseline `cbff61f…`, there were **20 production/package
files changed since the public 0.10.0 commit**, not just the header inspector. They also include static source
and helper parsing, plan/project evidence, registry-resource layout, public API
contract changes and editor preservation. A release from main must review and
state that complete delta. Calling such a release a header-only backport would
be incorrect. A truly narrow backport would need a separate dependency/diff review.

The suggested minor pre-1.0 version reflects the expanded public evidence model
and added closed-enum reason cases, which can break exhaustive Swift client
switches or older typed readers. The [intended 1.x compatibility contract](Compatibility-1.0.md)
is not already a published 1.x guarantee. Version selection still needs to be
recorded in the concrete release proposal.

Before any release: freeze the exact scope/source, update version and release
notes, pass required source/pilot/CodeQL checks on the preparation commit, bind
the manifest, privately accept the signed/notarized artifact, then obtain the
specific publication approval required by [Distribution](Distribution.md).
Public tag/release/checksum readback and Homebrew acceptance remain separate.
No new mappings, import rewriting, broad platform claim or completed 1.0 gate is
part of this maintenance recommendation.

## Subsequent G4 local result

The [recovery qualification](Recovery-1.0.md) subsequently passed eleven local
scenarios, including restored builds and fresh plans after handled/unhandled
signals and deliberate post-apply install/build failures. This advances G4
without changing the open G2/G3 boundaries or claiming protected integration.
The [0.11 proposal](ReleaseProposal-0.11.md) and [initial 1.0 scope proposal](ScopeProposal-1.0.md)
make the next release decisions concrete; neither publishes a release.

## Subsequent hosted evidence and G5 review

[PR #135](https://github.com/Alexsvensson99/PkgLift/pull/135), head
`bbabfdb5ca9d6d4d0537c471b28d671e1978aa44`, passed all 26 ordinary checks,
including CodeQL. The [pilot/source workflow](https://github.com/Alexsvensson99/PkgLift/actions/runs/36272014440)
ran against test-merge commit `c0b7263dc2ebdfd311e06987cdd75c881a2d0fa5`.
The source build and all seven building consumer jobs produced eight complete
same-job environment receipts: macOS 15.7.9 (24G830), arm64, Xcode 16.4
(16F6), Swift 6.1.2 and hosted runner image `20260907.0337.1`.

This supplies the hosted metadata missing in the earlier G2 rows above for
that exact PR run. It is not main-branch acceptance, exact macOS 14.0 runtime
coverage, a new toolchain support range or acceptance of a signed artifact.
Those historical local receipts remain bound to their original source; later
production changes require their own verification.

The focused G5 review at that PR head examined 50 of 460 tracked paths and
retained a bounded implementation/documentation follow-up. This is partial
repository coverage and does not close G5. The follow-up's verification must
bind its new source revision; green checks on the earlier head do not cover it.

## Merged safety follow-up and 0.11.0 source preparation

Updated 2026-09-27: PR #135 merged as
`4ff7b32dce8d706153ad682aa2332d0e61993738`, with a source tree identical to its
reviewed final head `fd202b2fccf6e15ea8e7608946ab48df299cb352`. The plan-output
follow-up now uses retained no-follow directory descriptors, private staging,
binding rechecks and atomic replacement. Its focused review retained no
findings; this does not turn the earlier partial G5 review into a complete
repository audit.

The final head passed 646 Swift tests (413 XCTest and 233 Swift Testing),
279 release-policy tests, 25 registry mappings, debug/release builds and
18 direct CLI plan-write cases across three output modes. The direct cases
checked normal writes and refused symlinked/dangling state directories,
non-directory state paths and symlinked plan destinations while preserving
outside files. Unit regressions additionally covered directory/FIFO plan
destinations and controlled binding changes. All 26 PR checks passed.
The subsequent exact-main [pilot/source](https://github.com/Alexsvensson99/PkgLift/actions/runs/36284796399),
[CodeQL](https://github.com/Alexsvensson99/PkgLift/actions/runs/36284796377) and
[Quality](https://github.com/Alexsvensson99/PkgLift/actions/runs/36284796380)
workflows also passed.

The [0.11.0 source preparation](ReleaseProposal-0.11.md) is now approved and
adds the version, dated changelog and [release notes](ReleaseNotes-0.11.0.md)
for the complete delta since 0.10.0. That new commit needs its own checks;
the evidence above belongs to the production baseline. Public distribution
remains 0.10.0, and the [1.0 scope proposal](ScopeProposal-1.0.md) remains
unadopted. No new registry mapping, support boundary or release approval is
implied.

## Remaining sequence

1. Resolve the exact G2 support envelope and unavailable macOS 14.0 runtime
   cell; qualify the final candidate in every adopted cell.
2. Complete a reviewed external positive G3 multi-target protocol when a suitable
   project is available. The bounded public search is recorded, not an instruction
   to restart it indefinitely. Never manufacture a positive result by editing
   AUTO classifications or upstream imports.
3. Preserve the completed local G4 drills and their signed-artifact limitations.
   Retain the verified bounded G5 follow-up and resolve the remaining broader
   safety/evidence claims.
4. Qualify and privately accept the exact candidate in G6, then obtain the
   separate publication approval required by Distribution.

This checkpoint preserves the six-gate plan. It does not close unavailable
macOS 14.0 evidence, the external positive multi-target case, G5 or release
acceptance. Local G4 results are complete for their documented scenarios.
