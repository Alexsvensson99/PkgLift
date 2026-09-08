# Local source inspection — local validation

Validated 2026-09-08 on Apple Silicon with Apple Swift 6.3.3. This is an
**unreleased local implementation**, based on main
`eefd6d09d18a2a517c26df121e871c4ad12c8c60`. Source version remains 0.6.2.
The [command contract](LocalSourceInspection.md) describes the new behavior.

## Completed checks

| Check | Result |
| --- | --- |
| Debug compilation | Passed; also rebuilt by the final full test run |
| Full test suite | 315 XCTest tests and 186 Swift Testing tests passed, zero failures (501 total) |
| Optimized build | `swift build -c release` passed |
| Registry validation | `swift run pkglift registry validate` passed, 22 mappings |
| Local pilots | Three original upstream inputs plus one controlled fixture produced their expected outcomes |
| Determinism | Repeated canonical JSON matched byte-for-byte; debug and optimized binaries emitted identical pilot reports |
| Input preservation | Input directory entries, modes, link targets and regular-file content hashes matched before/after every pilot |
| Failure exit | An unavailable source root emitted bounded JSON and exited 1 without leaking its private input path |
| Isolation | Existing generated-package checks and narrowed declaration-assessment checks passed; the new adapter does not reach migration, Xcode, registry or verification |
| Review | Independent read-only implementation review found no remaining material findings after corrections |

SwiftPM commands reused the existing cache with `--disable-sandbox`,
`--disable-automatic-resolution` and `--jobs 4`. Dependency versions were not
changed. User-cache write warnings were environmental; all final commands exited
successfully. The hosted CI toolchain (Xcode 16.4) has not been run for this local
change and remains a required gate before merge/release.

## Pilot results

| Exact original input | Pinned source commit | Local file outcome | Preserved declaration outcome |
| --- | --- | --- | --- |
| DeviceKit 5.8.0 | `56b997e8a61707218f9af09f32b2a1d1806fd792` | `verifiedObservedBytes`, one literal source, 127,908 bytes | `unsupported` |
| KeychainAccess 4.2.2 | `84e546727d66f1adc5439debad16270d0fdd04e7` | `unsupportedSelection`, wildcard refusal, no inventory | `unsupported` |
| SwiftSoup 2.11.3 | `d86f244ed497d48012782e2f59c985a55e77b3f5` | `unsupportedSelection`, wildcard and unresolved-version semantics retained, no inventory | `indeterminate` |
| Repository-owned local control | Synthetic, explicitly labeled | `verifiedObservedBytes`, two literal sources | `requiresGeneratedMetadata` |

All four successful report-producing cases exited 0. None proves whole-pod
compatibility or authorizes migration. In particular, DeviceKit's resource
bundle, platform, Swift/ARC and source-origin reasons remain intact.

Original normalized JSON inputs, licenses and immutable source links are recorded
in the existing [Podspec fixture provenance](../Tests/PkgLiftCocoaPodsTests/Fixtures/PodspecJSON/README.md)
for DeviceKit/KeychainAccess and in
[SwiftSoup's pinned Specs document](https://raw.githubusercontent.com/CocoaPods/Specs/1af217a399f1567f9b906ac593cd7867be58bde5/Specs/7/2/7/SwiftSoup/2.11.3/SwiftSoup.podspec.json).
Before execution, all 240 upstream file/link blobs across the three extracted
snapshots matched their pinned Git tree blob IDs. Ruby Podspecs were inert text;
no CocoaPods/Ruby or upstream code was executed. Fixture provisioning used public
downloads; the product and offline pilot harness did not use the network.

## Evidence binding and remaining gates

The optimized binary SHA-256 used for the final runtime checks was
`65c1f8b2158b2b74001a4bda87e3c988205727f3ebe38ba90c25904a52a17155`.
The SHA-256 of the sorted compact JSON map from each `Sources/` file,
`Package.swift` and `Package.resolved` to its content SHA-256 was
`004465c6ad6fdd845f189a961f89d58f7f67b1676548000b524c03c25b0ca8d8`
(92 files). Test, build, registry logs and machine-readable pilot receipts remain
in the task's local validation artifacts; their local filesystem paths are not
part of the portable product report.

Adversarial tests cover symlink roots/ancestors/files, same-byte source/Podspec
replacement, ancestor and descendant directory replacement, FIFO/special and
unreadable files, limits including streaming growth and total bytes, malformed
and duplicate-key JSON, traversal, case collisions, no partial inventory,
multiple simultaneous refusals, privacy and deterministic digest bindings.

Only the two new inspection files may retain declaration-assessment symbols;
generated-package symbols remain prohibited there. No registry mapping,
classification rule, migration operation, source version, release manifest,
signing workflow or Homebrew formula changed. Hosted CI, release preparation,
signing/notarization and public distribution remain separate outstanding gates.
