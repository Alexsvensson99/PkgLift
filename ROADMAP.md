# PkgLift Roadmap

PkgLift is evolving toward a comprehensive, evidence-driven dependency modernization toolkit for the Apple ecosystem. Safety gates remain more important than maximizing automatic conversions.

## v0.1.x: Foundation — Released

- Core Analyze → Plan → Migrate → Verify workflow.
- Conservative, version-gated CocoaPods-to-SwiftPM mappings.
- Typed migration actions and clean-worktree protection.
- Signed and notarized Apple Silicon distribution for macOS 14 or later.
- Homebrew installation support.

## v0.2.0: Safer Real-Project Support — Current

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

## v0.3.0: Broader Migration Coverage — Planned

Candidate priorities will be selected from real migration reports rather than assumed in advance:

- Safer support for additional static CocoaPods project shapes.
- More verified registry mappings backed by official upstream evidence.
- Improved reporting and CI integration for repeatable migrations.
- Evaluation of Carthage-to-SwiftPM migration without weakening the existing CocoaPods safety model.

## Future Horizons

- **Dependency Health**: Identify abandoned or poorly maintained dependencies and present evidence-backed alternatives.
- **Vulnerability Scanning**: Surface known vulnerabilities in the dependency graph without conflating advisories with migration eligibility.
- **CI Integration**: Provide official automation for dependency-policy and migration-readiness checks.
- **SBOM Generation**: Generate Software Bills of Materials for analyzed and migrated projects.
- **Additional Managers**: Expand only when each manager can be handled with deterministic parsing, reviewable plans, and verifiable mutation.
