# PkgLift Roadmap

PkgLift is continuously evolving. Our long-term vision is to be the ultimate dependency modernization toolkit for the Apple ecosystem.

## v0.1.x: CocoaPods → SwiftPM (Current)
- Core workflow: Analyze, Plan, Migrate, Verify.
- Conservative, version-gated CocoaPods to SwiftPM mappings.
- Safe project mutation with signed and notarized distribution.
- JSON output for analyze, plan, and verify automation.
- Homebrew installation support.

## v0.2.0: Improved Support & Ecosystem
- Read-only recursive project/workspace discovery.
- Explicit project selection inside multi-project workspaces.
- Safer workspace path normalization and containment checks.
- Literal string and symbol target syntax support.
- Optional build destination and configuration overrides.
- Stronger real-project discovery, workspace, and verification fixtures.

## v0.3.0: Carthage → SwiftPM
- Support for migrating projects using Carthage over to SwiftPM.
- Carthage `Cartfile` parser and dependency resolver.

## Future Horizons
- **Dependency Health**: Identifying abandoned or poorly maintained dependencies and suggesting actively maintained alternatives.
- **Vulnerability Scanning**: Alerting users to known vulnerabilities in their dependency graph during migration.
- **CI Integration**: Official GitHub Actions to ensure newly added dependencies conform to project policies.
- **SBOM Generation**: Generating Software Bill of Materials (SBOM) for migrated projects.
