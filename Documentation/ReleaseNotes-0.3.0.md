# PkgLift 0.3.0

Release date: 2026-08-18.

PkgLift 0.3.0 broadens evidence-backed CocoaPods migration coverage without relaxing the automatic-migration or preflight contracts. It remains a partial CocoaPods-to-SwiftPM migration tool for native Xcode projects: unsupported dependencies and project shapes stay visible for review instead of being converted by inference.

## Highlights

- Adds stable `MigrationReasonCode` and `MigrationReason` details to analysis candidates and plan entries while preserving the existing schema-1 `reasons` strings.
- Adds `analyze --fail-on blocked|unresolved|non-auto` for mutation-free readiness policy. Complete human, JSON, or portable-JSON output is written before a matching direct dependency returns status `1`.
- Supports bounded literal parenthesized forms such as `target('App') do` and `pod('Name')`, including the existing literal version and `modular_headers: true` forms, without executing Ruby.
- Expands the pinned read-only pilot matrix from seven to ten upstream projects. Application remains restricted to the repository-owned mixed Swift/Objective-C fixture.

## Exact registry coverage

- Adds `lottie-ios` → `Lottie` at the verified `3.2.2` Swift consumer boundary.
- Adds exact direct and subspec mappings for Firebase Auth, Firestore, Remote Config, and Storage at the verified `11.12.0` Swift and Objective-C consumer boundary.
- Keeps `Firebase`, `Firebase/Core`, unknown Firebase subspecs, and every other unmatched identity unmapped. Direct and subspec entries do not inherit from a base-pod fallback.

## Migration safety

- Every new automatic path still requires an exact verified registry identity, a supported stable lockfile version, a representable literal declaration, exact target attribution, a complete non-empty target profile, support for every consumer language, and unchanged preflight evidence.
- Interpolation, variables, arbitrary or extra options, external sources, postfix conditions, semicolons, multiline continuations, unbalanced syntax, unsupported executable statements, CocoaPods DSL method shadowing, raw control characters, non-ASCII whitespace, excessive nesting, and unsupported enclosing Ruby scopes remain non-automatic.
- Custom CocoaPods `source`, `workspace`, or `project` metadata is not discarded as automatic evidence; affected dependencies require review.
- Pilot write containment refuses pre-existing `.pkglift` paths, including symlinks, and upstream pilots remain read-only with portable output for uploaded analysis artifacts.

## Compatibility evidence

- The new pinned cases cover fastlane's CocoaPods example, FirebaseUI's Swift example, and Firebase's Legacy Auth Quickstart at immutable commits.
- The harness supports explicit Xcode-project selection without a workspace and bounded sparse checkouts for nested examples.
- Deterministic pilot reports include classification and stable reason-code counts, making deliberate refusals reviewable rather than treating them as failed migrations.

## Upgrade notes

- Regenerate every saved migration plan with PkgLift 0.3.0 before applying it. Executable plans are intentionally bound to the creating PkgLift version and current project evidence.
- Schema version remains `1`; `reasonDetails` is additive and older schema-1 analysis documents without it remain decodable. Reason metadata never authorizes migration by itself.
- `analyze --fail-on` evaluates only direct dependencies. Without the flag, analysis exit behavior is unchanged.
- PkgLift still does not migrate React Native, Flutter, Capacitor, Carthage, Kotlin Multiplatform, arbitrary Podfile hooks, or unsupported external dependency sources.

Signed and notarized release assets and the Homebrew formula are published only through the separately reviewed release-manifest workflow after the source-preparation commit is merged and every required check passes.
