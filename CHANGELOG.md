# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Deterministic target source profiles for Swift, Objective-C, Objective-C++, C, and C++ based only on PBX metadata.
- Explicit registry consumer-language evidence, including direct Firebase Analytics, Crashlytics, and Messaging mappings verified from `11.12.0`.
- Conservative Carthage, React Native, Flutter, and Capacitor integration detection with typed, privacy-minimized diagnostics summaries.
- `--portable-json` for `analyze` and `plan`, with local-path and URL-secret redaction and a versioned portable-output marker.
- A repository-owned mixed Swift/Objective-C SDWebImage fixture and four additional immutable read-only upstream pilot cases.
- Compatibility, support, and private vulnerability-reporting guidance.

### Changed
- Repeated declarations of the same exact pod name are represented by one deterministic dependency and plan entry while retaining every literal declaration origin.
- Analysis and plan JSON include explicitly named source, dependency, candidate, and plan-entry counts; human analysis and diagnostics keep their direct-dependency totals scoped to unique identities.
- Xcode target environments now honor project and target xcconfig precedence across every build configuration, while targets, SwiftPM packages, and linked products use deterministic ordering.
- End-to-end apply validation now runs only against a repository-owned fixture; all pinned upstream projects are analysis, plan, and dry-run only.

### Fixed
- Static helper attribution handles bounded literal calls and nested-target inheritance without assigning helper declarations to the wrong target.
- Conditional, configuration-limited, and otherwise unrepresentable pod declarations cannot become `AUTO`.
- Valid CocoaPods lockfiles produced after the last pod is removed are accepted as an empty dependency set, while inconsistent lockfiles still fail closed.

### Security
- `AUTO` now requires explicit exact target attribution and non-empty literal registry-declaration provenance during both classification and migration preflight; older schema-1 plans without that evidence must be regenerated.
- Migration preflight refuses a saved `AUTO` entry when current Podfile, lockfile, registry, configuration, action, or target evidence has changed since planning.
- Parent declarations include statically proven nested targets that use default or complete inheritance; the literal CocoaPods-only option `modular_headers: true` remains migratable, while uncertain helper dispatch, other declaration options, conditions, and inheritance fail closed to review.
- `AUTO` and preflight require a complete, non-empty target profile whose every language is explicitly supported by the exact registry mapping; older or manipulated plans without this evidence are refused.
- Confirmed Carthage, React Native, Flutter, and Capacitor integration prevents automatic migration without parsing or modifying those ecosystems.

## [0.2.0] - 2026-08-15

### Added
- Read-only recursive discovery for Xcode projects and workspaces beneath the selected root.
- Explicit `--workspace` and `--project` selection, including selection of one referenced project from a multi-project workspace.
- Static Podfile parsing for single-quoted, double-quoted, simple-symbol, and quoted-symbol target names, including conservative escaped-quote support.
- Build verification overrides for configuration, destination, SDK, and derived-data path.
- `pkglift diagnostics`, which writes a local, deterministic, versioned JSON report containing minimized toolchain, project-shape, classification, issue, readiness, and Git-state summaries.
- A pinned real-project pilot matrix covering a positive migration, mixed classifications, and a conservative refusal.
- A licensed positive end-to-end pilot that establishes a CocoaPods baseline build, reviews the complete `AUTO` set, proves a mutation-free dry run, applies only `SDWebImage`, refreshes the remaining pod, resolves SwiftPM, and builds the migrated workspace.

### Changed
- Project and workspace discovery now skips generated dependency and build trees while supporting nested repository layouts.
- Workspace package resolution receives the already validated scheme and derived-data path instead of relying on Xcode inference.
- CI uses least-privilege permissions, pinned Actions, concurrency controls, bounded jobs, debug and release builds, repository-quality validation, and non-duplicated pull-request execution.
- README onboarding, migration-report intake, registry-contribution guidance, build-verification documentation, and pilot documentation now reflect the conservative real-project workflow.

### Fixed
- Relative derived-data paths are resolved beneath the explicit `--path` rather than the process working directory.
- Workspace package resolution no longer fails when Xcode requires an explicit scheme.
- Double-quoted Ruby interpolation forms such as `#@variable` and `#$global` remain dynamic instead of being misclassified as literal target names.
- Diagnostics count aggregated analysis issues once and refuse both valid and dangling symbolic-link output paths.

### Security
- Project and workspace paths are canonicalized after symlink resolution and must remain contained by `--path`.
- Workspace `group`, `container`, `absolute`, and `self` locations are normalized without accepting unsupported location schemes.
- Computed target or pod names remain dynamic and are never inferred by the static parser.
- Build verification rejects empty or control-character option values, passes every setting as a separate process argument, and redacts derived-data paths from recorded settings.
- Diagnostics omit source code, Podfile contents, names, URLs, changed filenames, arbitrary error messages, and absolute user paths; reports are written atomically with mode `0600` and are never uploaded automatically.
- Real-project pilots use immutable upstream commits, no write credentials, no repository secrets, explicit licensing boundaries, reviewed `AUTO` sets, and strict mutation/diff checks.

## [0.1.2] - 2026-08-15

### Security
- `AUTO` now requires an exact pod/subspec mapping and a stable lockfile version at or above the registry's verified SwiftPM minimum version.
- Base pod mappings can no longer be inherited by arbitrary transitive subspecs.
- Install hooks, dynamic Ruby, `script_phase`, `use_frameworks!`, `inherit! :search_paths`, and `abstract_target` all force manual review.

### Changed
- Registry schema 1 remains load-compatible when `swiftpm.minimumVersion` is absent, but such mappings are review-only; malformed minimum versions fail validation.
- All ten bundled mappings now include conservative upstream-verified minimum versions and verification dates.
- Plans generated by v0.1.1 are rejected by v0.1.2 preflight and must be regenerated.

## [0.1.1] - 2026-08-12
### Added
- Reproducible Developer ID signing and Apple notarization for release binaries.
- Homebrew tap distribution for Apple Silicon on macOS 14 or later.
- Manual distribution validation that never creates a public GitHub Release.

### Changed
- Registry validation limits Swift build parallelism and no longer runs redundantly for release tags.
- Release packaging verifies architecture, deployment target, checksum, direct execution, symlink installation, and typed missing-bundle behavior.

## [0.1.0] - 2026-08-11
### Added
- Core `analyze`, `plan`, `migrate`, and `verify` commands.
- Static Podfile parser (no Ruby execution required).
- Xcode project manipulation via `XcodeProj`.
- Foundation for the Dependency Registry.
- Auto/Review/Blocked/Unknown classification system.
- Safe, atomized migration strategies.

### Changed
- AUTO plans now contain executable, typed remove-package-link actions.
- Migration preflight refuses missing versions, missing/ambiguous targets, stale action metadata, and conflicting existing package requirements before mutation.
- Podfile editing preserves target blocks and unrelated Ruby during partial migration.
- Git safety explicitly supports clean, dirty, and non-Git projects.
- Verification checks package-product-target linkage.
