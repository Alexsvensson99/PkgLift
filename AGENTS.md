# Agent Guidelines

**For Coding Agents (Codex, Gemini, Claude, etc.) working on PkgLift:**

## Architecture Overview
PkgLift is a Swift package with multiple modules (Core, CocoaPods, Migration, Registry, Verification, Xcode, CLI). It strictly adheres to Swift 6 concurrency (Sendable, isolated domains). Ensure your code is thread-safe and type-safe.

## Build and Test
- **Build**: `swift build`
- **Test**: `swift test`
- **Registry Validation**: `swift run pkglift registry validate`

## Safety Invariants (CRITICAL)
- **NEVER** weaken migration safety for tests. Tests should prove safety, not bypass it.
- **NEVER** classify a dependency as `AUTO` without concrete evidence from the Registry or Project Graph.
- Always use typed errors instead of fatal errors or force unwrapping (`!`).
- Do not mutate project files (`.xcodeproj`) except through `PkgLiftXcode`, orchestrated by `PkgLiftMigration`.

- `Sources/PkgLiftCore/`: Core types and logic.
- `Sources/PkgLiftCocoaPods/`: Podfile and lockfile parsing, plus Podfile-target mapping.
- `Sources/PkgLiftMigration/`: Classifier/planner, atomic migration orchestration, and write sequencing.
- `Sources/PkgLiftXcode/`: Xcode project and workspace inspection plus file mutations.
- `Sources/PkgLiftRegistry/`: Mapping registry loading and validation.
- `Sources/PkgLiftVerification/`: Structural and build verification.
- `Sources/PkgLiftCLI/`: Command-line entrypoint and orchestration.
- `Registry/`: YAML files mapping CocoaPods to SwiftPM.

## Registry Contribution
When asked to add a mapping, format it as YAML matching the model documented in `Documentation/Registry.md`. Run the validation command to ensure correctness before committing.
