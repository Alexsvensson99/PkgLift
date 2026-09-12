# PkgLift 0.7.1 — Clearer local inspection diagnostics

Local Podspec source inspection now starts with a plain-language result and
explains inspection reasons before presenting the separate declaration assessment.
It clarifies unsupported patterns, root source selection, zero-based declaration
indexes and normalized assessment evidence paths. An absent inventory is
explicitly distinguished from a project that has no source files.

Canonical JSON, exit codes, inspection limits, privacy boundaries and migration
eligibility are unchanged. This release does not expand glob patterns, generate
packages or broaden `AUTO`. Keep the original Podspec intact when investigating
unsupported selections. See the [inspection contract](LocalSourceInspection.md).

## Development quality

CI shares debug compilation across build, tests and registry validation, and
one verified release binary across both pilot groups. All required checks and
ten pinned pilot cases remain, with separate CodeQL analysis. New policy tests
reject skipped validation, ignored failures and mismatched artifact evidence.
See [continuous integration](ContinuousIntegration.md).

## Upgrade compatibility

The source version is `0.7.1`. Regenerate saved migration plans after upgrading;
plans are bound to the PkgLift version that created them.

## Local candidate verification

On 2026-09-12, the 0.7.1 candidate passed 504 Swift tests, 58 release/CI policy
tests, debug and arm64 release builds, and registry validation for 22 mappings.
Non-signing archive checks passed, including checksum validation, byte-preserving
extraction, installed-style symlink execution and missing-registry failure.
The optimized 0.7.1 executable repeated eight pinned upstream Podspec cases with
unchanged input trees and byte-identical JSON relative to the published 0.7.0
baseline. These observations do not constitute signed distribution acceptance
or migration approval.

## Release status

[PkgLift 0.7.1](https://github.com/Alexsvensson99/PkgLift/releases/tag/v0.7.1)
was published on 2026-09-12 at
`a97aa7e627b72be25d9a79774709bb7d728dc8b0`, following the reviewed manifest and
successful main checks. The [signed distribution run](https://github.com/Alexsvensson99/PkgLift/actions/runs/34672420166)
completed Apple notarization and artifact acceptance; the
[publication run](https://github.com/Alexsvensson99/PkgLift/actions/runs/34672414870)
published the verified archive. [Homebrew update #13](https://github.com/Alexsvensson99/homebrew-tap/pull/13)
was merged and its supported macOS CI passed the formula's full installation
checks. Future releases retain the separate approval steps in the
[distribution contract](Distribution.md).
