# Local source inspection 0.8 — validation record

Recorded **2026-09-12** for the unreleased 0.8 feature change, before 0.8.0
release preparation. At that time the source version was `0.7.1`. The local
checks and all eight debug/release field-pilot comparisons below **passed**.
This historical record does not establish 0.8.0 candidate-version verification,
CI completion, a merge or publication.

## Contract under test

The explicit `--source-selection flat-swift-globs` mode uses schema 2,
`pkglift.local-source-inspection/v2`, `ascii-relative-path/v2` and
`root-literals-and-flat-swift-globs/v1`. It accepts literal `+` in path components
and only nonrecursive `<literal-directory>/*.swift` patterns. The default v1
grammar, canonical JSON and text remain unchanged. The
[inspection contract](LocalSourceInspection.md) specifies the exact limits,
no-follow reads, two directory passes, content rereads and complete-or-refused
inventory. Neither mode changes the original declaration assessment or supplies
provenance, package-validity, S1 or migration evidence.

## Completed local checks

| Check | Recorded result |
| --- | --- |
| Debug build | Passed |
| arm64 release build | Passed |
| Swift tests | 547 passed: 323 XCTest and 224 Swift Testing |
| Release/CI policy tests | 58 passed |
| Registry validation | 22 mappings passed |
| Repository YAML validation | 10 YAML files, 6 SHA-pinned workflows and 2 issue forms passed |

The inspection suites cover supported and unsupported selection, v1/v2 profile
separation, literal `+`, deterministic inventory binding, privacy, unsafe entry
types, observed races and resource bounds. See
[inspection tests](../Tests/PkgLiftInspectionTests/),
[CLI tests](../Tests/PkgLiftCLITests/PodspecCommandTests.swift) and
[repository YAML validation](../Scripts/validate-repository-yaml.rb).
Passing these checks does not create an atomic filesystem snapshot.

## Pinned field-pilot inputs and observed results

**Pilot status: 8/8 passed in both debug and release.** Source links identify
exact pinned upstream commits. SHA-256 values bind the unchanged original
Podspec JSON bytes. Stable local inputs were reconstructed from the original
receipts' commit-pinned archives after verifying every archive SHA-256; their
paths, types, bytes and modes matched the earlier private source inventories.
No Podspec was simplified or regenerated to obtain a positive result.

| Original Podspec | Pinned source commit | Original JSON SHA-256 | Observed v2 result, debug and release |
| --- | --- | --- | --- |
| DeviceKit 5.8.0 | [`56b997e8a61707218f9af09f32b2a1d1806fd792`](https://github.com/devicekit/DeviceKit/tree/56b997e8a61707218f9af09f32b2a1d1806fd792) | `8297066280041cd75175167c32d79ee772a4b95a29c85ffc99cd468a6f3f15a5` | `verifiedObservedBytes`: 1 file, 127,908 bytes |
| KeychainAccess 4.2.2 | [`84e546727d66f1adc5439debad16270d0fdd04e7`](https://github.com/kishikawakatsumi/KeychainAccess/tree/84e546727d66f1adc5439debad16270d0fdd04e7) | `4608b1366f705163ed9804e812bec02925bf6b61bd9924b08c482eb2be34187c` | `verifiedObservedBytes`: 1 file, 123,497 bytes |
| SnapKit 5.7.1 | [`2842e6e84e82eb9a8dac0100ca90d9444b0307f4`](https://github.com/SnapKit/SnapKit/tree/2842e6e84e82eb9a8dac0100ca90d9444b0307f4) | `cc2fedc2cafd2a371adb68455282f463f4d8c3b6f30a8a58bc8eb0e58b7981e2` | `verifiedObservedBytes`: 37 files, 127,738 bytes |
| SwiftSoup 2.11.3 | [`d86f244ed497d48012782e2f59c985a55e77b3f5`](https://github.com/scinfu/SwiftSoup/tree/d86f244ed497d48012782e2f59c985a55e77b3f5) | `5a978471734bc41e109ff6e813d7a02d08faa6c3163d443ea14e8226503457ca` | `unsupportedSelection`: recursive glob and unknown selection semantics |
| Alamofire 5.10.2 | [`513364f870f6bfc468f9d2ff0a95caccc10044c5`](https://github.com/Alamofire/Alamofire/tree/513364f870f6bfc468f9d2ff0a95caccc10044c5) | `2482d7ef687cbc00fb08c033febedf84172c47e849183876097bb314ebb5fa13` | `unsupportedSelection`: recursive glob and unknown selection semantics |
| CryptoSwift 1.10.0 | [`f2a627b84c1ff96f21ac2fcb623ab36142dd5512`](https://github.com/krzyzanowskim/CryptoSwift/tree/f2a627b84c1ff96f21ac2fcb623ab36142dd5512) | `e1da64dfdf81fa8aef911b44cb6ae36f05f2cf18dc36c3176070ff1d0eb73257` | `unsupportedSelection`: recursive glob and unknown selection semantics |
| RxSwift 6.9.0 | [`5dd1907d64f0d36f158f61a466bab75067224893`](https://github.com/ReactiveX/RxSwift/tree/5dd1907d64f0d36f158f61a466bab75067224893) | `d1eb6bff38f3ae173b483fe0983dd24e44aa868a9f31ceca97eac71bed380176` | `unsupportedSelection`: recursive globs and excluded sources |
| SDWebImage 5.21.1 | [`b62cb63bf4ed1f04c961a56c9c6c9d5ab8524ec6`](https://github.com/SDWebImage/SDWebImage/tree/b62cb63bf4ed1f04c961a56c9c6c9d5ab8524ec6) | `605947964a1867a5c9e3493ab05ed5b7f08a490413015ea85adc07fe1ddd88ca` | `unsupportedSelection`: subspec scope, missing root selection and unknown semantics |

Both executables produced byte-identical v1 JSON **and text** against published
0.7.1. V2 JSON and text also matched between debug and release. Independent file
digests and inventory binding, unchanged original assessments, repeatable JSON,
identical JSON from copied physical roots, privacy checks and per-run unchanged
input bytes, modes and link targets all passed. The five unsupported cases
retained empty inventories and omitted the inventory hash.

## Historical feature-validation identity and limits

The tested source files were included in this feature change, based on main
`a97aa7e627b72be25d9a79774709bb7d728dc8b0`, while the source version was
`0.7.1`. The following binary SHA-256 values identify those historical local
executables only:

| Executable | SHA-256 |
| --- | --- |
| Debug candidate | `aa83e89bd56ebe8bbc88a7340c015890087360e01ef982c133c857843655ad2f` |
| arm64 release candidate | `9ca27ae3bedeae1f0ec12da2167c7577559e314ae9ce3f38860b6da5e7be8b84` |
| Published 0.7.1 reference | `008baaaa10d40d5fdbd68b973e5aaabd4b717d2bae3d97706226514bc600b599` |

The reference archive SHA-256 was independently checked against the public
release asset: `cec8f04d732ec8c2c3d901c1b4b6d1a6215fd7ba0ef51a222b8e95e99aec553d`.
These historical fingerprints do not identify 0.8.0 candidate executables and
are not signed 0.8.0 distribution artifacts.

CI, merge and public distribution require their own exact-source evidence and
are outside this local validation record. No third-party source files or private
local paths are included here. These eight selected cases are not an estimate of
CocoaPods ecosystem coverage. Inspection observations do not establish atomic
snapshots, provenance, buildability or migration approval.
