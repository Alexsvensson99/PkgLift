# PkgLift 0.9.0 — Verified Swift consumer mappings

[PkgLift 0.9.0](https://github.com/Alexsvensson99/PkgLift/releases/tag/v0.9.0)
is published and available through the
[Homebrew tap](https://github.com/Alexsvensson99/homebrew-tap/blob/main/Formula/pkglift.rb).

## Verified mappings

The release adds exact registry mappings for KeychainAccess 4.2.2 and
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

## Release evidence

[Preparation PR #111](https://github.com/Alexsvensson99/PkgLift/pull/111)
merged as `c4d9a83d1e0ef228e0012d41935b18be306c799a`.
[Manifest PR #112](https://github.com/Alexsvensson99/PkgLift/pull/112) then
merged as its manifest-only child
`eaecabf570d06ccff905ef45723c5e49d126c0ba`, the verified tag target.
The feature baseline at `733964a3c9fa93ed4ab213d83cbf96a482f1b36b` passed
570 Swift tests, 68 release/CI policy tests, validation of 24 registry mappings,
and 21 main checks including CodeQL. This includes full KeychainAccess and
DeviceKit consumer, migration and build coverage. The concrete consumer builds
prove only versions 4.2.2 and 5.8.0; `swiftpm.minimumVersion` remains the
existing threshold policy for later stable lockfile versions when all other
gates pass.

## Verified distribution

The 0.9.0 preparation passed 570 Swift tests, 68 policy/helper tests and
validation of 24 registry mappings. All 21 ordinary checks on the final
manifest commit passed, including CodeQL and the full consumer migrations.

- [Protected publication run 35015938010](https://github.com/Alexsvensson99/PkgLift/actions/runs/35015938010)
  completed successfully for the final tag commit.
- [Signing run 35016017395](https://github.com/Alexsvensson99/PkgLift/actions/runs/35016017395)
  produced a Developer ID-signed distribution accepted by Apple notarization.
  The downloaded CLI passed strict signature, quarantine execution, version,
  registry, installed-style symlink and missing-registry checks.
- The publisher's selected run and staged files were verified before production
  approval. Both public release files were then downloaded and matched the
  accepted signed artifact byte for byte.
- [Homebrew PR #15](https://github.com/Alexsvensson99/homebrew-tap/pull/15)
  passed style, strict online audit, installation, signature/version/registry
  checks, formula test and uninstall before merge. The public formula was
  read back with version 0.9.0 and the verified archive checksum.

Public archive SHA-256:
`397ebaf330b28045fac3d45d5b58e84c36163f439d29f8ea06108b2611b6e3a8`.

## Release status

The public tag, release files and Homebrew formula were verified after
publication. The distributed CLI is Developer ID-signed and Apple-notarized
under the [distribution contract](Distribution.md).
