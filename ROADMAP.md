# PkgLift Roadmap

PkgLift is evolving toward a comprehensive, evidence-driven dependency modernization toolkit for the Apple ecosystem. Safety gates remain more important than maximizing automatic conversions.

## v0.1.x: Foundation — Released

- Core Analyze → Plan → Migrate → Verify workflow.
- Conservative, version-gated CocoaPods-to-SwiftPM mappings.
- Typed migration actions and clean-worktree protection.
- Signed and notarized Apple Silicon distribution for macOS 14 or later.
- Homebrew installation support.

## v0.2.0: Safer Real-Project Support — Released

- Recursive discovery for nested Xcode projects and workspaces.
- Explicit project/workspace selection when discovery is ambiguous.
- Canonical workspace path normalization and root-containment checks.
- Literal string and symbol target syntax support without evaluating Ruby.
- Reproducible build verification with explicit scheme, configuration, destination, SDK, and derived-data settings.
- Local privacy-preserving diagnostics with deterministic JSON and secure file handling.
- Hardened, de-duplicated CI and repository-quality validation.
- Three pinned real-project classification pilots.
- A licensed positive end-to-end migration that proves baseline build, reviewed apply, remaining CocoaPods integration, SwiftPM resolution, and final build.

Release evidence and the completed work breakdown are recorded in the [v0.2.0 tracker](https://github.com/Alexsvensson99/PkgLift/issues/26).

## v0.2.1: Compatibility Evidence and Release Hardening — In development

- Deterministic Swift, Objective-C, Objective-C++, C, and C++ target profiling from PBX metadata.
- Consumer-language evidence in the registry and a fail-closed language contract for `AUTO` and migration preflight.
- Direct Firebase Analytics, Crashlytics, and Messaging mappings at the verified `11.12.0` boundary.
- Detection and conservative refusal for Carthage plus React Native, Flutter, and Capacitor project integrations.
- Portable analyze and plan JSON with local-path and URL-secret redaction.
- Seven immutable read-only upstream pilots and one repository-owned mixed Swift/Objective-C end-to-end fixture.
- Explicit compatibility, support, and private vulnerability-reporting documentation.
- Required CI summary gates, dependency updates, and Swift code scanning before release.

## v0.3.0: Broader Migration Coverage — Planned

Candidate priorities will be selected from real migration reports rather than assumed in advance:

- Safer support for additional static CocoaPods project shapes.
- More verified registry mappings backed by official upstream evidence.
- Improved reporting and CI integration for repeatable migrations.
- Evidence gathering for additional dependency managers without treating detection as migration support.

## Future Horizons

- **Dependency Health**: Identify abandoned or poorly maintained dependencies and present evidence-backed alternatives.
- **Vulnerability Scanning**: Surface known vulnerabilities in the dependency graph without conflating advisories with migration eligibility.
- **CI Integration**: Provide official automation for dependency-policy and migration-readiness checks.
- **SBOM Generation**: Generate Software Bills of Materials for analyzed and migrated projects.
- **Additional Managers**: Expand only when each manager can be handled with deterministic parsing, reviewable plans, and verifiable mutation.
