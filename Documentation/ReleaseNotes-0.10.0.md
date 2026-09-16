# PkgLift 0.10.0 — CryptoSwift Swift/iOS mapping

[PkgLift 0.10.0](https://github.com/Alexsvensson99/PkgLift/releases/tag/v0.10.0)
is the current public release at `7d976d70e66a584e2e25db9852ac0e53bb6201b9` and is available through the
[Homebrew tap](https://github.com/Alexsvensson99/homebrew-tap/blob/main/Formula/pkglift.rb).

## Released scope

The release adds one exact registry mapping: CocoaPods `CryptoSwift` to the
`CryptoSwift` product from `https://github.com/krzyzanowskim/CryptoSwift`.
It uses schema 2 and is limited to complete Swift-only iOS consumer targets
with a deployment target of iOS 15 or later.

The concrete admission build covered CryptoSwift 1.10.0. It compiled identical
repository-owned consumer bytes through CocoaPods and SwiftPM, bound all 113
compiled core Swift source files to the reviewed upstream revision, and checked
the named built privacy resources in both integrations. The feature was merged
by [PR #114](https://github.com/Alexsvensson99/PkgLift/pull/114); its completed
[feature CI run 35051095147](https://github.com/Alexsvensson99/PkgLift/actions/runs/35051095147)
and the [verified consumer-mapping record](VerifiedConsumerMappings.md) retain
the exact migration, source and resource evidence.

`swiftpm.minimumVersion` keeps its existing threshold policy. Stable lockfile
versions at or above 1.10.0 can qualify for `AUTO` only when every existing
mapping, project-graph, language and platform gate also passes. The concrete
consumer build does not prove later CryptoSwift versions, other languages, or
other platforms.

## Boundaries

This release does not add runtime cryptographic validation or runtime privacy
testing. The privacy checks prove the presence and parsed semantics of the
reviewed manifest in the built consumers only.

CryptoSwift remains non-automatic for Objective-C or mixed-language targets,
platforms other than iOS, deployment targets below iOS 15, missing or ambiguous
target evidence, unknown subspecs, versions below 1.10.0, `use_frameworks!`,
and every other existing non-automatic project condition. It does not change
package generation, source-provenance policy, or the general `AUTO` safety
model.

## Upgrade compatibility

PkgLift 0.10.0 changes the plan version. Regenerate plans created by 0.9.0
before applying them with 0.10.0; saved plans remain
bound to the PkgLift version that created them.

## Distribution

The public Apple Silicon archive targets macOS 14 or later, is Developer
ID-signed and Apple-notarized, and includes the adjacent registry bundle. The
same verified release is available through Homebrew. The protected publication
and distribution requirements are documented in the
[distribution contract](Distribution.md).
