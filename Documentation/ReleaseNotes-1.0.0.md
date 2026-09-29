# PkgLift 1.0.0 — Verified, conservative migration contracts

Status: **published on 2026-09-29.** [Release `v1.0.0`](https://github.com/Alexsvensson99/PkgLift/releases/tag/v1.0.0)
targets M, `207ff4e92b2fc4ed39c5fd8a4c2270eb0093faf9`. The public archive SHA-256 is
`402a8bec302af870ae6e86955e310e0b95cd2386123790e17924edf5946a84e1`; its extracted binary SHA-256 is
`4e7997c6a03e19cf41d6413d90066dd17064f2975feddd066d5ef606556f998b`. [Homebrew formula](https://github.com/Alexsvensson99/homebrew-tap/blob/2317ae83bc8e1095877c8f79bfd53dbc1b7945e3/Formula/pkglift.rb).

Final prepared source F, `1839cbfe614c3affeecd6c790bb43ca2053a334a`, came from PR #138. M is
its manifest-only child from PR #139 and is the public tag/archive source.
F's private candidate is not the released archive. The [final Release run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36615292778)
and [public readback](Evidence/Qualification-1.0/public-distribution.json) bind these separate states.

## What 1.0 establishes

PkgLift 1.0 freezes the documented meanings of its public CLI commands and
options, JSON reports and plans, reason codes, configuration and registry
schemas, and six public Swift library products. Additive report fields remain
possible. Breaking changes require the documented deprecation and major-version
policy.

Saved plans are executable evidence, not portable instructions for a different
binary. A plan created by an earlier PkgLift version must be regenerated with
1.0.0 before dry run or apply. Do not edit its producer version, classification
or evidence fields.

Version 1.0 also includes the safety work prepared but never publicly released
as 0.11.0:

- bounded registry-source and C-family header-import evidence;
- typed refusal for missing, unsupported, conflicting or incomplete evidence;
- no-follow, binding-checked and atomically replaced `.pkglift/plan.json` writes;
- stricter target attribution, retained-CocoaPods validation and executable-plan
  freshness checks;
- preservation checks for unrelated schemes, breakpoints, source, resources and
  existing SwiftPM integration.

PkgLift still does not rewrite imports, execute arbitrary Podfile Ruby, invent
package metadata, migrate local or external Git pods, run `pod install`, or turn
an uncertain dependency into `AUTO`.

## Initial positive support envelope

The 1.0 positive qualification claim is intentionally narrower than everything
PkgLift can discover or safely refuse. It covers the exact mapping, target,
language, platform and version combinations backed by the candidate evidence
matrix, including the repository-owned complete and partial migration fixtures
and the named AWS single-target source qualification bound to unchanged
production/registry/harness inputs through the final candidate.

A positive external multi-target or workspace migration is explicitly deferred
from the initial 1.0 envelope. PkgLift retains project/workspace discovery,
explicit selection, target attribution, sibling preservation and conservative
refusal behavior for those shapes, but 1.0 does not present a repository fixture
or a refusal as an external positive success. That deferred cell remains
post-1.0 qualification work.

Automatic migration remains conditional on complete live evidence. `REVIEW`,
`BLOCKED` and `UNKNOWN` are successful safety outcomes when the contract cannot
justify a write.

## Runtime and toolchain evidence

The release is Apple Silicon-only. The [environment matrix](Environments-1.0.md#final-10-evidence-matrix)
records three distinct exact-artifact cells:

| Signed M cell | Observed environment | Result |
| --- | --- | --- |
| Core runtime | macOS 14.8.9 (23J631), arm64; image `20260831.0302.1` | Signature/quarantine, version/registry, analyze, plan, inert dry run and structural apply passed. No Xcode consumer build was performed in this job. |
| Hosted consumers | macOS 15.7.9 (24G830), Xcode 16.4 (16F6), Swift 6.1.2, CocoaPods 1.17.0, iOS Simulator SDK 18.5 (22F76) | Complete mixed-language migration/build, PartialMixed with retained CocoaPods and conservative Hammerspoon refusal passed. |
| Local runtime and consumers | macOS 27.0 (26A428), Xcode 27.0 (27A266a), Swift 6.4, CocoaPods 1.17.0, iOS Simulator SDK 27.0 (24A430), arm64 | Core runtime plus PartialSwift, PartialMixed, PartialSwiftCoexistence and complete mixed migration/build passed using the same signed M archive; consumer deployment target 15.0. |

The original full-mixed local baseline encountered the pinned pod's iOS-9
setting, which Xcode 27 rejects. A fresh baseline and migrated build both
passed with explicit iOS 15/arm64 settings, matching the selected local consumer
cell. The failed baseline and successful retry retain separate receipts. No
migration classification or safety check was weakened.

Historical dirty-checkout source/API/recovery evidence remains separate from
these signed M checks. macOS 14 deployment metadata and Homebrew's `:sonoma`
minimum do not prove exact macOS 14.0; the two Xcode/Swift cells do not qualify
every intermediate or later version.

## Exact-candidate release acceptance

| Check | Actual acceptance |
| --- | --- |
| Developer ID, hardened runtime, secure timestamp, notarization, quarantine, version and bundled registry | Passed in [M Release run 36615292778](https://github.com/Alexsvensson99/PkgLift/actions/runs/36615292778), attempt 1. |
| Complete and partial migration/build; conservative refusal | Passed in the isolated, read-only-permission M consumer job, using the same archive/binary/bundle hashes. [Cloud receipt](Evidence/Qualification-1.0/cloud-final-M-acceptance.json). |
| macOS 14 core runtime | Passed using the same M archive; `consumerBuildTested: false`. [Cloud receipt](Evidence/Qualification-1.0/cloud-final-M-acceptance.json). |
| Local macOS 27 runtime and four consumer flows | Passed before production approval. [Local receipt](Evidence/Qualification-1.0/local-final-M-acceptance.json). |
| Public tag, checksum, binary and Homebrew | Public `v1.0.0` targets M; downloaded public bytes and formula/test evidence recorded in [distribution readback](Evidence/Qualification-1.0/public-distribution.json). |

The named external AWS partial migration and FirebaseUI/Hammerspoon refusals
come from the separate [G3 run 36606015426](https://github.com/Alexsvensson99/PkgLift/actions/runs/36606015426)
on P. Their production/registry/fixture/harness inputs are unchanged through F
and M. They are not the manifest's F positive-pilot run 36610656058, which
qualifies repository-owned consumers and keeps source-only upstream intake
separate. The external positive multi-target/workspace case remains deferred.

The public archive contains only `pkglift` and its adjacent registry bundle;
private acceptance evidence is retained separately.

## Upgrade guidance

After installing the published 1.0 release, confirm the executable and bundled
registry before creating a new plan:

```bash
pkglift version
pkglift registry validate
pkglift analyze
pkglift plan
pkglift migrate
```

Review the complete plan and keep the worktree clean before separately choosing
`pkglift migrate --apply`. Refresh dependencies that remain under CocoaPods with
your normal reviewed `pod install` process, then run structural and build
verification using the project's explicit scheme and destination.

## Release evidence

[Final qualification](Qualification-1.0.md) and [distribution readback](Evidence/Qualification-1.0/public-distribution.json)
record the protected publication and exact public artifacts. The `v1.0.0` tag
retains its frozen preparation documentation; this living post-release record
adds actual publication and installation evidence without changing that tag.
A merged documentation change is separate from a verified website deployment.
