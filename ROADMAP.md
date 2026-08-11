# PkgLift Roadmap

PkgLift is continuously evolving. Our long-term vision is to be the ultimate dependency modernization toolkit for the Apple ecosystem.

## v0.1.0: CocoaPods → SwiftPM (Current)
- Core workflow: Analyze, Plan, Migrate, Verify.
- Basic CocoaPods to SwiftPM mappings.
- Safe project mutation.
- JSON output for analyze, plan, and verify automation.

## v0.2.0: Improved Support & Ecosystem
- Enhanced Xcode project support (complex target graphs, custom configurations).
- Significantly expanded registry mappings.
- Homebrew installation support.
- Stronger project/workspace discovery and verification fixtures.

## v0.3.0: Carthage → SwiftPM
- Support for migrating projects using Carthage over to SwiftPM.
- Carthage `Cartfile` parser and dependency resolver.

## Future Horizons
- **Dependency Health**: Identifying abandoned or poorly maintained dependencies and suggesting actively maintained alternatives.
- **Vulnerability Scanning**: Alerting users to known vulnerabilities in their dependency graph during migration.
- **CI Integration**: Official GitHub Actions to ensure newly added dependencies conform to project policies.
- **SBOM Generation**: Generating Software Bill of Materials (SBOM) for migrated projects.
