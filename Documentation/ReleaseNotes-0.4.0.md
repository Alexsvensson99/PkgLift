# PkgLift 0.4.0

Release date: 2026-08-22.

PkgLift 0.4.0 adds fail-closed, analysis-only evidence for bounded external CocoaPods Git sources. Automatic migration scope is unchanged: external sources remain visible for review and never authorize an `AUTO` action.

## Highlights

- Adds typed `sourceProvenance` evidence to analysis dependencies and migration-plan entries for supported literal `:git` declarations, reconciled with CocoaPods lockfile `EXTERNAL SOURCES` and `CHECKOUT OPTIONS` evidence.
- Derives deterministic Git-evidence statuses for immutable, mutable, unpinned, credential-bearing, incomplete, conflicting, ambiguous, unsupported-URL, and unsupported-syntax cases.
- Removes URL user information, credentials, queries, and fragments at the parser trust boundary. Raw source URLs are not retained in standard or portable JSON.
- Reuses one checksum-verified, source-SHA-bound PkgLift artifact across the isolated read-only pilot matrix.

## Migration safety

- External Git provenance is analysis-only. Every external source remains `REVIEW`, `BLOCKED`, or `UNKNOWN`, never `AUTO`, including a complete immutable tag or commit.
- PkgLift does not execute Podfile Ruby, contact Git repositories, resolve private authentication, generate Podspecs, model local `:path` provenance, or migrate external sources automatically.
- `migrate --apply` compares saved and current safely comparable external provenance with version, declaration-origin, and target-attribution evidence. Added, removed, changed, redacted, malformed, incomplete, conflicting, credential-bearing, or otherwise lossy evidence refuses mutation.
- Supported immutable evidence requires matching declaration and lockfile repository/reference evidence plus a complete checkout commit. Branches are mutable and missing references are unpinned.

## Compatibility evidence

- Two independent pinned, read-only real-project pilots exercise external Git refusal paths: XcodeBenchmark and Hammerspoon.
- Both require matching analysis and plan provenance, stable reason codes, unpinned and incomplete-tag evidence, and a complete no-`AUTO` result.
- Every pilot consumer verifies the shared artifact's archive and executable checksums, architecture, registry bundle, source SHA, workflow-run identity, and producer attempt before analysis.

## Upgrade notes

- Schema version remains `1`. `sourceProvenance` is additive, and existing schema-1 documents without it remain decodable.
- Regenerate saved migration plans before applying them. Executable plans remain bound to the creating PkgLift version and current project evidence.
- `sourceProvenance` supplies evidence only; it never broadens registry coverage or migration eligibility.

Signed and notarized release assets are published only through the separately reviewed release-manifest workflow after the source-preparation commit is merged and every required check passes. The Homebrew formula is updated afterward with the verified archive SHA under its own validation and approval gate.
