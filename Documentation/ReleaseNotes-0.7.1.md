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

This is preparation for an unreleased 0.7.1 candidate. Publication requires the
merged preparation commit and its own successful main CI, followed by reviewed
release metadata and signed/notarized distribution checks. No release manifest
is included in this product-preparation change. GitHub and Homebrew publication
remain separate approval steps under the [distribution contract](Distribution.md).
