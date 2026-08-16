# PkgLift 0.2.1

Released 2026-08-16.

PkgLift 0.2.1 strengthens the evidence required for automatic migration and broadens compatibility testing without broadening unsafe mutation. It remains a partial CocoaPods-to-SwiftPM migration tool for native Xcode projects.

## Highlights

- Profiles Swift, Objective-C, Objective-C++, C, and C++ target sources deterministically from PBX metadata without reading source contents.
- Requires a complete target profile and explicit registry support for every consumer language before `AUTO`; mixed Swift and Objective-C targets require both.
- Adds exact `FirebaseAnalytics`, `FirebaseCrashlytics`, and `FirebaseMessaging` mappings at the verified `11.12.0` boundary.
- Detects Carthage plus React Native, Flutter, and Capacitor integration and prevents automatic migration instead of guessing ownership.
- Adds `--portable-json` to `analyze` and `plan`, with versioned local-path and URL-secret sanitization while preserving the full executable plan locally.

## Migration safety

- Saved automatic plans must retain literal declaration provenance, exact target attribution, target-language evidence, and supported mapping languages through preflight. Older or manipulated plans missing this evidence are refused before mutation and must be regenerated.
- Conditional, configuration-limited, dynamically dispatched, or otherwise unrepresentable pod declarations cannot become `AUTO`.
- Static helper attribution now accounts for bounded calls and nested-target inheritance.
- Empty CocoaPods lockfiles produced after migrating the final pod are accepted only when their remaining sections are internally consistent.
- Xcconfig environment inference is confined to regular files beneath the selected project root and fails closed on symlink escapes or bounded-read violations.

## Compatibility evidence

- A repository-owned iOS fixture proves one target can consume SDWebImage from both Swift and Objective-C before and after migration.
- Its end-to-end pilot establishes a CocoaPods baseline, requires exactly one reviewed `AUTO`, proves a mutation-free dry run, applies only to a disposable fixture copy, resolves SwiftPM, builds for the simulator, and verifies unchanged source and resource hashes.
- Seven exact-commit upstream pilots remain read-only: Amazon IVS Grid Feed, LoodosCase, V2ex-Swift, Tinode, XcodeBenchmark, Hammerspoon, and AcknowList.

## Maintenance and security

- Stable Registry, CodeQL, pinned-pilot, and mixed-language-pilot gates are visible on every pull request while expensive work runs only for relevant paths.
- The complete upstream pilot matrix runs weekly to detect Xcode-runner or pinned-source drift.
- Dependabot monitors SwiftPM and GitHub Actions weekly.
- Swift CodeQL analysis runs on macOS, and repository validation rejects mutable third-party Action references.
- Compatibility, support, private vulnerability reporting, JSON, registry, pilot, and migration-safety documentation now share the same explicit boundaries.

## Upgrade notes

- Regenerate any saved migration plan with PkgLift 0.2.1 before applying it. Preflight intentionally refuses plans produced by another PkgLift version or plans that lack the new evidence.
- Review portable JSON before sharing it: dependency and target names may remain. Use `pkglift diagnostics` for a more privacy-minimized support artifact.
- Carthage and detected cross-platform integration are analysis boundaries in this release, not migration targets.

Signed and notarized release assets and the Homebrew formula are published only through the separately reviewed release-manifest workflow after the source-preparation commit is merged and all required checks pass.
