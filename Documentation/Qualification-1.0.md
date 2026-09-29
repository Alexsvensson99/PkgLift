# PkgLift 1.0 candidate qualification

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
| Public library inventory | 1,931 symbols across six modules; repeated compiler capture matched after removing provenance URIs | [API contract and baseline](API-1.0.md) |
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

## Remaining exact-candidate gates

1. Review and merge source preparation; require the protected main source,
   consumer, CodeQL and quality checks for that exact commit. Bind the Xcode 16.4
   cell to its own same-job receipts.
2. Run the pinned real-project protocol: AWS positive partial migration plus
   FirebaseUI and Hammerspoon conservative refusals. These cannot substitute for
   the explicitly deferred multi-target/workspace positive cell.
3. Accept the private signed candidate: Developer ID identity, notarization,
   archive identity, full/partial migration and refusal in an unprivileged job,
   plus the same signed archive's observed macOS 14 runtime. Record the actual
   patch/build rather than inferring 14.0 support.
4. Merge the manifest as the sole direct child of source preparation; repeat
   signed acceptance for its exact SHA and publish through protected controls.
5. Verify the public archive, checksum, tag/source identity and Homebrew
   installation. Update the public release record with actual results.

The current standing 1.0 mandate authorizes this sequence when its gates pass.
This preparation record does not claim that any remaining gate has already run.
