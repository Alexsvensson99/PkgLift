# PkgLift 0.8.0 — Bounded flat Swift source selection

PkgLift 0.8.0 is an unreleased release candidate. [PkgLift 0.7.1](https://github.com/Alexsvensson99/PkgLift/releases/tag/v0.7.1) remains the public release.

## Opt-in local inspection mode

`pkglift podspec inspect` now offers the explicit opt-in mode:

```sh
pkglift podspec inspect \
  --podspec Example.podspec.json \
  --source-root ./Example \
  --source-selection flat-swift-globs
```

The mode accepts the existing literal root-relative `.swift` paths and exactly
one additional selector form: `<literal-directory>/*.swift`. It selects only
immediate, case-sensitive `.swift` children of that literal directory. A literal
`+` is permitted in v2 directory and filename components, for example
`Sources/Constraint+Layout.swift`.

The mode has its own report identity: schema 2,
`pkglift.local-source-inspection/v2`, `ascii-relative-path/v2`, and
`root-literals-and-flat-swift-globs/v1`. The default remains the v1,
literal-only command and preserves its existing path grammar, JSON and text
contract.

## Boundaries

This is not general glob support. Recursive patterns, exclusions, wildcard
directory components, other wildcard syntax, subspecs and non-root selections
remain unsupported. A flat glob does not add migration behavior, source
provenance, package-validity evidence, synthetic S1 evidence, or `AUTO`
eligibility. It does not generate packages or expand registry mappings.

The observation remains bounded and complete-or-refused: empty matches,
overlaps, unsafe entries, limit exhaustion and observed changes fail without a
partial inventory. See the [local source-inspection contract](LocalSourceInspection.md)
for the exact syntax, filesystem checks and report fields.

## Upgrade compatibility

The source version is `0.8.0`. Regenerate saved migration plans after upgrading;
plans are bound to the PkgLift version that created them.

## Candidate verification

On 2026-09-12, the source-version `0.8.0` candidate passed 547 Swift tests, 58
release/CI policy tests, debug and optimized arm64 builds, and validation of all
22 registry mappings. Repository YAML validation passed for 10 files, six
SHA-pinned workflows and two issue forms. Non-signing packaging checks verified
archive checksums, byte-preserving extraction, the arm64/macOS 14 target,
installed-style symlink execution and the typed missing-registry failure.

All eight pinned cases passed again in both debug and release. DeviceKit
observed 1 file / 127,908 bytes, KeychainAccess 1 / 123,497 and SnapKit 37 /
127,738; the other five retained their existing refusals. V1 JSON and text
remained byte-identical to public 0.7.1. V2 output matched between the two new
binaries and the accepted feature candidate. Independent source/inventory
digests, unchanged original assessments, copied-root portability, privacy and
per-run unchanged input checks all passed. The unchanged input identities and
profile limits are documented in the
[historical feature-validation record](LocalSourceInspection-0.8-Validation.md).

| Local 0.8.0 executable | SHA-256 |
| --- | --- |
| Debug | `9f0d75eeb0d7ad93337920b33faf42b3baed80d5e43a306dacca8f93e193ca6e` |
| arm64 release | `e09413ef89cfd4fe522387669182eaafecb0cadb85c3404827f7b39cec263a7f` |

These are local candidate fingerprints, not signed distribution artifacts.

## Release status

This source-preparation change does not publish a tag, GitHub Release or
Homebrew update. Signed artifact acceptance and public distribution retain
their separate checks and approval gates in the
[distribution contract](Distribution.md).
