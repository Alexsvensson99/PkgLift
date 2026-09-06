# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.1] - 2026-09-06

PkgLift 0.6.1 — Interrupted migration recovery and rollback hardening.

### Fixed
- Restore the original Podfile and complete `.xcodeproj` when `migrate --apply`
  observes SIGINT or SIGTERM before commit. After successful rollback, exit with
  conventional status 130 or 143 respectively.
- Attempt restoration of every original after a handled migration error; report
  rollback failures separately and retain recovery state if restoration fails.
- Detect incomplete migration state before parsing a potentially partial project
  or permitting another apply, including with `--allow-dirty`.

### Security
- Reserve and synchronize a minimal transaction marker before preparing backups
  or mutating originals. Unclean termination cannot run rollback; surviving
  recovery state causes the next apply to fail closed.
- Preserve the known-good backup of an incomplete migration. Only a backup with
  a valid completed receipt matching the current migration context may be reused;
  legacy, malformed, mismatched, or active recovery state is never overwritten.

### Changed
- Set the source version to `0.6.1`. Saved plans remain bound to the creating
  PkgLift version and must be regenerated after upgrading.

## [0.6.0] - 2026-09-05

Released as a signed and notarized [GitHub download](https://github.com/Alexsvensson99/PkgLift/releases/tag/v0.6.0)
and through [Homebrew](https://github.com/Alexsvensson99/homebrew-tap/pull/9).

### Added
- Add a pure, in-memory `GeneratedPackageBlueprintAssessor` in `PkgLiftCocoaPods` for one synthetic Swift-library shape, with explicit snapshot, source, topology, completeness and consumer evidence.
- Recompute and compare the complete v0.5 assessment from the exact Podspec bytes. Bind the snapshot using SHA-256 digests of those Podspec bytes, snapshot identifier bytes and canonical inventory JSON. Preserve the original assessment while allowing only the exact S1 source-selection reason to be discharged in a separate blueprint result.
- Add four deterministic outcomes and 25 typed reason codes, a repository-owned S1 fixture, and regression coverage for missing, contradictory, unsupported, malformed and oversized evidence.
- Add bounded evidence/result JSON entry points and privacy-bounded portable blueprint output containing digests and numeric references instead of raw names and paths.

### Changed
- Set the source version to `0.6.0`. Existing migration plans must be regenerated because preflight binds plans to the creating PkgLift version.

### Security
- Reject direct-decoder bypasses, duplicate or unknown JSON fields, unsupported profiles, noncanonical paths and ordering, invalid bindings and oversized portable output through typed errors.
- Retain the v0.5 semantic contract and all migration safety gates. Source existence, contents and provider claims remain caller assertions; S1 is not a package-validity or provenance certificate.
- Keep generated-package symbols confined to the reviewed analysis files. The new API performs no filesystem or network access, package generation, project mutation or new `AUTO` classification.

## [0.5.0] - 2026-09-01

### Added
- Add a bounded, offline, in-memory Podspec JSON inspector pinned to CocoaPods Core 1.17.0 semantics, with typed limits and errors at the untrusted JSON boundary.
- Add an immutable recursive semantic model for root, library-subspec, and raw `ios`, `osx`, `tvos`, `watchos`, and `visionos` scopes. It records exact RFC 6901 evidence paths for supported platform, default-subspec, file, header, resource, dependency, linkage, vendored-input, module, header-layout, compilation, build-setting, ARC, and file-selection declarations.
- Add a schema-1, deterministic SwiftPM declaration assessment pinned to Swift tools 6.0. The four fail-closed outcomes retain sorted, privacy-bounded reasons for metadata requirements, indeterminate evidence, and unsupported declarations.
- Add immutable upstream and repository-authored fixtures with documented provenance and SHA-256 checksums, plus a complete v0.5.0 declaration/reason-code evidence matrix and release notes.

### Changed
- Public semantic-model and assessment values are immutable, `Sendable`, `Equatable`, and `Codable`. Decoding rejects unsupported profiles or schemas, noncanonical reason order, duplicates, invalid evidence paths, and outcomes inconsistent with their strongest reason.

### Fixed
- Reject malformed or ambiguous configuration, lockfile versions, registry minimum versions, migration requirements, workspace paths, and verify-command options through typed fail-closed errors instead of permissive fallbacks.

### Security
- Unknown or deferred CocoaPods fields, malformed modeled evidence, duplicate JSON keys or sibling subspecs, ambiguous defaults, unsupported inheritance or platform merge behavior, and unknown semantic profiles fail closed.
- Dynamic dependency, build-setting, and unsupported-field names are represented in assessments only by deterministic indices. Raw keys, values, flags, source URLs, macros, and paths are never copied into the assessment artifact.
- Podspec inspection and assessment remain analysis-only library APIs. They do not read files, execute Ruby, invoke CocoaPods, access the network, generate `Package.swift`, change registry mappings, alter serialized analysis or plan schemas, mutate Xcode projects, or authorize `AUTO`.
- Linkage and vendored paths remain opaque: PkgLift does not expand globs, traverse paths, follow symlinks, inspect binaries, infer SwiftPM binary targets, or assign semantics to the unsupported `static_library` key.

## [0.4.0] - 2026-08-22

### Added
- Additive typed external Git `sourceProvenance` on analysis dependencies and migration-plan entries, assembled from bounded literal Podfile declarations and CocoaPods lockfile `EXTERNAL SOURCES` and `CHECKOUT OPTIONS` evidence.
- Deterministic Git evidence statuses for supported immutable, mutable, unpinned, credential-bearing, incomplete, conflicting, ambiguous-repository, unsupported-URL, and unsupported-syntax cases, with stable migration reason codes.

### Changed
- The static Podfile parser recognizes one literal `:git` URL with at most one literal `:branch`, `:tag`, or `:commit` in supported parenthesized or whitespace forms without executing Ruby.
- Git repository comparison keeps HTTPS identities distinct from SSH while normalizing SSH URLs and SCP-style syntax to the same SSH identity. Immutable tag evidence requires matching Podfile and lockfile repository/reference evidence plus a full checkout commit; a direct commit must also equal the checkout commit.
- Migration preflight compares safely comparable external provenance plus version, declaration origins, and target attribution against current analysis, including added, removed, or changed evidence. Lossy/redacted evidence refuses apply rather than relying on equal redaction markers. External-source provenance never authorizes an `AUTO` action.

### Security
- Git credentials, URL user information, queries, and fragments are removed at the parser trust boundary and are not retained in standard or portable JSON. Unsupported values fail closed to redacted evidence.
- All external sources remain `REVIEW`, `BLOCKED`, or `UNKNOWN`, never `AUTO`. Local `:path` provenance, network repository resolution, Podspec generation, and automatic external-source migration remain outside v0.4.0.

## [0.3.0] - 2026-08-18

### Added
- Stable `MigrationReasonCode` and `MigrationReason` details on analysis candidates and migration-plan entries while preserving legacy schema-1 `reasons`.
- Mutation-free `analyze --fail-on blocked|unresolved|non-auto` CI policy that prints complete human, JSON, or portable-JSON output before returning status `1` for matching direct dependencies.
- Static support for literal parenthesized `target('App') do` and `pod('Name')` calls, including supported literal version and `modular_headers: true` arguments.
- An exact `lottie-ios` to `Lottie` mapping verified at `3.2.2`, plus exact direct and subspec mappings for Firebase Auth, Firestore, Remote Config, and Storage verified at `11.12.0`.
- Three pinned read-only project cases for fastlane's CocoaPods example, FirebaseUI's Swift example, and Firebase's Legacy Auth Quickstart.

### Changed
- Human analysis prints every classification reason code, message, and available remediation; pinned pilot reports include deterministic reason-code counts.
- The pinned pilot harness supports explicit project selection without a workspace and sparse partial checkouts for nested roots; canonical containment rejects symlink escapes, uploaded JSON uses the URL-secret-safe portable contract, and the complete read-only matrix now contains ten cases.

### Security
- New registry identities and parenthesized syntax remain `REVIEW` unless exact version, declaration, target, project-risk, and consumer-language evidence satisfies the unchanged `AUTO` and preflight gates.
- `Firebase`, `Firebase/Core`, unknown Firebase subspecs, computed Ruby, raw control characters, non-ASCII whitespace, excessive scope nesting, multiline literals or continuations, unrecognized executable statements, CocoaPods DSL method shadowing, unsupported enclosing blocks, heredocs, extra options or expression tails, postfix conditions, semicolons, and unbalanced calls or scopes remain unmapped or non-automatic; only column-zero Ruby block comments and `__END__` data are ignored, so invalid indented markers cannot create automatic dependency evidence.

## [0.2.1] - 2026-08-16

### Added
- Deterministic target source profiles for Swift, Objective-C, Objective-C++, C, and C++ based only on PBX metadata.
- Explicit registry consumer-language evidence, including direct Firebase Analytics, Crashlytics, and Messaging mappings verified from `11.12.0`.
- Conservative Carthage, React Native, Flutter, and Capacitor integration detection with typed, privacy-minimized diagnostics summaries.
- `--portable-json` for `analyze` and `plan`, with local-path and fail-closed URL-secret redaction and a versioned portable-output marker.
- A repository-owned mixed Swift/Objective-C SDWebImage fixture and four additional immutable read-only upstream pilot cases.
- Compatibility, support, and private vulnerability-reporting guidance.
- Weekly SwiftPM and GitHub Actions updates through Dependabot, plus SHA-pinned Swift CodeQL analysis on macOS.

### Changed
- Repeated declarations of the same exact pod name are represented by one deterministic dependency and plan entry while retaining every literal declaration origin.
- Analysis and plan JSON include explicitly named source, dependency, candidate, and plan-entry counts; human analysis and diagnostics keep their direct-dependency totals scoped to unique identities.
- Xcode target environments now honor project and target xcconfig precedence across every build configuration, while targets, SwiftPM packages, and linked products use deterministic ordering.
- End-to-end apply validation now runs only against a repository-owned fixture; all pinned upstream projects are analysis, plan, and dry-run only.
- Registry, CodeQL, and both pilot workflows run their required validation on every pull request and main-branch push; candidate-controlled path filters cannot turn skipped work into a green gate, and the complete read-only pilot matrix also runs weekly.

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
- Xcode environment inference reads only regular xcconfig files contained by the selected project root and refuses symlink escapes or bounded-read violations.
- Repository validation rejects mutable third-party Action references instead of relying only on maintainer convention.

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
