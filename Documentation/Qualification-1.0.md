# PkgLift 1.0 qualification

This record distinguishes local candidate-source verification from protected
integration, signed-artifact acceptance and public distribution. The initial
scope follows the [adopted support envelope](ScopeProposal-1.0.md). External
positive multi-target/workspace qualification remains deferred after 1.0.

## Local source preparation: 2026-09-29

The preparation checkout is based on main
`c5c32ee8e3598975a97dc53207b29596724f65f1` with the recorded source version change
to `1.0.0` and release-contract/workflow changes. It was intentionally dirty
during local qualification. The [paired build source inventory](Evidence/Recovery-1.0/local-2026-09-29-build.json)
binds all 194 current manifests, production sources, Swift/C/H tests and registry
inputs; documentation or workflow preparation is not represented as a clean main
commit. Raw logs and disposable consumers remain in task-owned external storage.

| Check | Actual result | Evidence |
| --- | --- | --- |
| Swift build/test and registry | Debug/test and release builds passed; 413 XCTest plus 233 Swift Testing cases passed; 25 mappings validated | [Source record](Evidence/Qualification-1.0/local-2026-09-29-source.json) |
| Public library inventory | 1,931 symbols across six modules; repeated compiler capture matched after removing provenance URIs and doc-comment positions | [API contract and baseline](API-1.0.md) |
| Recovery procedure | All 11 scenarios and 97 commands passed; all 194 logs and source inputs independently reconciled | [Recovery record](Recovery-1.0.md#candidate-source-rerun-on-2026-09-29) |
| Swift partial migration | Baseline and fresh migrated builds passed; exact AUTO set, retained CocoaPods manifest and consumer preservation passed | [PartialSwift](Evidence/Qualification-1.0/local-2026-09-29-PartialSwift-summary.json), [same-run environment](Evidence/Qualification-1.0/local-2026-09-29-PartialSwift-environment.json) |
| Mixed-language partial migration | The same checks passed for Swift/Objective-C SDWebImage migration with KeychainAccess retained | [PartialMixed](Evidence/Qualification-1.0/local-2026-09-29-PartialMixed-summary.json), [environment](Evidence/Qualification-1.0/local-2026-09-29-PartialMixed-environment.json) |
| Existing SwiftPM coexistence | Partial migration passed with DeviceKit package objects and exact existing pin preserved | [PartialSwiftCoexistence](Evidence/Qualification-1.0/local-2026-09-29-PartialSwiftCoexistence-summary.json), [environment](Evidence/Qualification-1.0/local-2026-09-29-PartialSwiftCoexistence-environment.json) |
| Migration-integrity review | No confirmed critical/high defect in the reviewed CLI path; library caller documentation disposition addressed | [Targeted review](SafetyReview-1.0.md) |
| Registry claim audit | 25 upstream mapping identities/products/boundaries substantiated; four rows have linked compiled consumers; legacy AUTO policy unchanged | [Evidence ledger](RegistryEvidence-1.0.md) |

The local consumer cell is Apple Silicon, macOS 27.0 (26A428), Xcode 27.0
(27A266a), Swift 6.4, CocoaPods 1.17.0 and iOS Simulator SDK 27.0 (24A430),
with Debug, arm64 and iOS deployment 15.0. This is not a claim that every mapping
has been built on every selected toolchain. Environment captures mark the dirty
preparation checkout incomplete; all host/toolchain probes passed and the source
inventory binds the tested bytes.

The local release binary (without Developer ID signing or notarization) SHA-256 is
`640195cd5500c0b9974cffb5501e65a8ab822a063948d52d8d857d498527307d`.
The actual local CLI also passed the new runtime helper's core analyze, plan,
inert dry run, apply and structural verification sequence. That development
exercise excluded signed/quarantine acceptance and cannot satisfy the release gate.

## Final protected and public qualification

The accepted source and artifact identities are deliberately separate. P is the
PR #137 preparation merge `70575a92e59792e87d8c2d3f536fca9cd20aef33`. PR [#138](https://github.com/Alexsvensson99/PkgLift/pull/138)
produced final prepared source F, `1839cbfe614c3affeecd6c790bb43ca2053a334a`. PR
[#139](https://github.com/Alexsvensson99/PkgLift/pull/139) added only `.github/releases/v1.0.0.json`,
producing its sole direct child M, `207ff4e92b2fc4ed39c5fd8a4c2270eb0093faf9`. The production source,
registry, fixtures and qualification harnesses are unchanged from P through F to
M; the P→F change fixes the release refusal invocation and its policy test, and
F→M adds only the release manifest. The source binding preserves the original
local build/recovery/API receipt identities.

| Gate | Actual result and identity | Evidence |
| --- | --- | --- |
| P private candidate diagnostic | Run 36606019838 did not pass overall: the refusal invocation used `hammerspoon` instead of `hammerspoon-workspace`. Its package/runtime/full/partial successes do not make it an accepted release run. | [Diagnostic run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36606019838) |
| Final source F | Main positive-pilot run 36610656058 passed the seven selected repository-owned consumer cases; this is the manifest's `positivePilotWorkflowRun`. | [F main run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36610656058), [source qualification](Evidence/Qualification-1.0/source-qualification.json) |
| Non-deferred external G3 | AWS Grid Feed positive partial migration/build and FirebaseUI/Hammerspoon refusals passed on P in the separate real-project workflow. Unchanged production/registry/fixture/harness bytes bind that source evidence through F and M. This was not a signed M archive run. | [G3 run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36606015426), [source binding and case receipts](Evidence/Qualification-1.0/source-qualification.json) |
| Private F candidate | All jobs passed, including signed full/partial/refusal acceptance and macOS 14 core runtime. Its archive is distinct from M's. | [Private F run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36610712835) |
| Manifest M protected checks | Source/pilot, CodeQL and quality checks passed for M. | [Source/pilot](https://github.com/Alexsvensson99/PkgLift/actions/runs/36615269853), [CodeQL](https://github.com/Alexsvensson99/PkgLift/actions/runs/36615269699), [quality](https://github.com/Alexsvensson99/PkgLift/actions/runs/36615269808) |
| Exact signed M cloud acceptance | Release run 36615292778, attempt 1, passed all three jobs: package/sign/notary, consumer full/partial/refusal and macOS 14 runtime. | [M Release run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36615292778), [cloud receipt](Evidence/Qualification-1.0/cloud-final-M-acceptance.json) |
| Exact signed M local acceptance | Core runtime plus PartialSwift, PartialMixed, PartialSwiftCoexistence and full mixed-language baseline/migration/build passed with the same downloaded signed M bytes on the independently observed local macOS 27 cell. | [Portable local receipt](Evidence/Qualification-1.0/local-final-M-acceptance.json), [raw aggregate](Evidence/Qualification-1.0/local-signed-M-acceptance.json) |
| Protected publication and public readback | Published on 2026-09-29; `v1.0.0` targets M. Downloaded public archive, checksum and extracted binary match the accepted candidate. | [Publication run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36615269741), [public Release](https://github.com/Alexsvensson99/PkgLift/releases/tag/v1.0.0), [readback](Evidence/Qualification-1.0/public-distribution.json) |
| Homebrew | Formula points to the verified public archive; PR CI passed, including the hosted installation/test/uninstall lifecycle; main CI passed. Local formula style passed; local strict audit was unavailable because Command Line Tools were outdated, and no local installation was started. | [Tap PR](https://github.com/Alexsvensson99/homebrew-tap/pull/17), [main CI](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/36619431921), [formula](https://github.com/Alexsvensson99/homebrew-tap/blob/2317ae83bc8e1095877c8f79bfd53dbc1b7945e3/Formula/pkglift.rb), [readback](Evidence/Qualification-1.0/public-distribution.json) |

The exact accepted M archive SHA-256 is
`402a8bec302af870ae6e86955e310e0b95cd2386123790e17924edf5946a84e1`, binary
SHA-256 `4e7997c6a03e19cf41d6413d90066dd17064f2975feddd066d5ef606556f998b`,
and registry-bundle tree SHA-256
`14e6d8975c87f7ad88b6d92bd43319662db9a43893f134ca0000abf0234e5510`.
These identify M's accepted artifact, not the historical local development binary
or F's private archive. Public byte equality is recorded separately in the
[distribution readback](Evidence/Qualification-1.0/public-distribution.json).

## Environment and workload boundaries

| Evidence cell | Observed environment | Qualified workload |
| --- | --- | --- |
| Signed M core runtime | macOS 14.8.9 (23J631), arm64; runner image `macos14` / `20260831.0302.1` | Signature/quarantine, version/registry, analyze, plan, inert dry run and structural apply. `consumerBuildTested: false`; no consumer compilation on this host. |
| Signed M cloud consumers | macOS 15.7.9 (24G830), arm64; image `macos15` / `20260907.0337.1`; Xcode 16.4 (16F6), Swift 6.1.2; CocoaPods 1.17.0; iOS Simulator SDK 18.5 (22F76), macOS SDK 15.5 (24F74) | Complete mixed-language migration/build, PartialMixed with retained CocoaPods, and the Hammerspoon conservative refusal. |
| Signed M local runtime and consumers | macOS 27.0 (26A428), arm64; Xcode 27.0 (27A266a), Swift 6.4; CocoaPods 1.17.0; iOS Simulator SDK 27.0 (24A430), macOS SDK 27.0 (26A425); no hosted runner image | Core runtime and all four named consumer flows, Debug/arm64 with iOS deployment 15.0. |
| Historical local source qualification | The intentionally dirty preparation checkout and its original local binary/build identities recorded above | Build/test/API/recovery and partial-consumer source evidence; not substituted for signed M acceptance. |

The first local full-mixed baseline stopped before migration because SDWebImage's
CocoaPods target defaulted to iOS 9, below Xcode 27's supported range. Its exit-65
receipt is preserved. A fresh full baseline and migrated build then passed with
`IPHONEOS_DEPLOYMENT_TARGET=15.0` and `ARCHS=arm64` applied consistently to both
builds and package resolution. Actual Xcode build-request records confirm those
settings. The original wrapper, three passing partial cases, canonical SSD
helper and failed attempt remain unchanged; the [local receipt](Evidence/Qualification-1.0/local-final-M-acceptance.json) binds
both wrappers and the failure/retry evidence. No classification or migration
safety check changed.

The [full environment matrix](Environments-1.0.md#final-10-evidence-matrix)
keeps runtime, source and consumer workloads separate. Neither the macOS 14
package minimum nor Homebrew's `:sonoma` requirement proves exact 14.0. The two
Xcode/Swift cells do not imply every intermediate or later version.

The external positive multi-target/workspace cell remains **deferred post-1.0**
under the [adopted protocol](ScopeProposal-1.0.md#what-the-deferred-g3-cell-would-require).
Repository fixtures, read-only upstream intake and safe refusals do not fill it.
