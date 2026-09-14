# PkgLift 0.9.0 — Verified Swift consumer mappings

PkgLift 0.9.0 is an unreleased release candidate. [PkgLift
0.8.0](https://github.com/Alexsvensson99/PkgLift/releases/tag/v0.8.0) remains
the public release.

## Verified mappings

The candidate adds exact registry mappings for KeychainAccess 4.2.2 and
DeviceKit 5.8.0. Both are limited to Swift-only iOS consumers with a deployment
target of iOS 15 or later. Their admission evidence compiles the same consumer
through CocoaPods and SwiftPM; DeviceKit additionally checks generated source
and the built privacy resource. The feature baseline then completed the full
consumer, migration and build path for both mappings in
[run 34905481290](https://github.com/Alexsvensson99/PkgLift/actions/runs/34905481290).
See [verified consumer mappings](VerifiedConsumerMappings.md) for the exact
consumer, source and resource evidence.

Registry schema 2 binds the supported consumer platform and deployment target.
Older clients reject a schema-2 mapping rather than silently ignoring that
boundary; schema-1 mappings retain their existing behavior. The existing
`swiftpm.minimumVersion` policy is unchanged: later stable lockfile versions at
or above the minimum can qualify for `AUTO` when all other checks pass. The
concrete consumer build evidence covers only 4.2.2 and 5.8.0, respectively.

## Boundaries

The new mappings do not extend to Objective-C, mixed-language consumers, other
platforms, unmapped subspecs, missing or non-stable lockfile versions, versions
below the mapping minimum, missing or lower deployment targets, or unsupported
project evidence. Those cases remain non-automatic under the
existing classification and migration-preflight rules. This release does not
add package generation, source provenance, or a new path to `AUTO` without the
existing exact registry and project-graph evidence.

## Upgrade compatibility

The source version is `0.9.0`. Regenerate saved migration plans after upgrading;
plans are bound to the PkgLift version that created them.

## Candidate acceptance

Candidate-specific proof belongs to the source-version `0.9.0` preparation
pull-request and exact-main checks, followed by separately recorded private
artifact acceptance under the [distribution contract](Distribution.md). The
feature baseline at `733964a3c9fa93ed4ab213d83cbf96a482f1b36b` passed 570 Swift
tests, 68 release/CI policy tests, validation of 24 registry mappings, and 21
main checks including CodeQL. Those results, including the full KeychainAccess
and DeviceKit consumer/migration/build run, are preparation-base evidence rather
than a substitute for the candidate-specific acceptance record.

## Release status

No 0.9.0 release manifest, public tag, GitHub Release, or Homebrew update is
present. Any public distribution remains subject to the separate artifact and
protected approval gates in the [distribution contract](Distribution.md).
