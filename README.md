# PkgLift

**Modernize Apple dependencies safely.**

PkgLift analyzes native Xcode projects, builds a dependency migration plan, and safely moves supported dependencies from CocoaPods to Swift Package Manager.

No blind conversions. No guesswork.

**Analyze → Plan → Migrate → Verify**

## What PkgLift Does

PkgLift automates the tedious and risky process of migrating an iOS/macOS project from CocoaPods to Swift Package Manager (SwiftPM).

```bash
$ pkglift analyze
Analyzing project MyProject.xcodeproj...
Found 12 dependencies in Podfile.
Registry matches: 10/12
Classification complete. Run `pkglift plan` to review.

$ pkglift plan
Generating migration plan...
- Alamofire: AUTO (Supported via SwiftPM)
- SnapKit: AUTO (Supported via SwiftPM)
- ObscureLibrary: UNKNOWN (Not found in registry)
Plan saved to .pkglift/plan.json. Please review.

$ pkglift migrate
Dry run mode. Add --apply to execute the migration plan.

$ pkglift migrate --apply
Applied 2 validated AUTO migrations.
Run `pod install`, then run `pkglift verify`.

$ pkglift verify
Verifying build...
Build succeeded!
```

## Why PkgLift Exists

With CocoaPods effectively entering maintenance mode and going read-only, the Apple developer ecosystem is consolidating around Swift Package Manager. However, manual migration is risky, tedious, and prone to errors. PkgLift provides a paved, verifiable path to SwiftPM without the headache of manual dependency resolution and Xcode project file manipulation.

## Safety Philosophy

PkgLift operates on a strict safety model. Every dependency is classified before migration:
- **AUTO**: The plan contains an exact pod/subspec mapping, a stable lockfile version at or above the registry's verified SwiftPM minimum, a package URL, product, and existing destination target. Only these entries are executable.
- **REVIEW**: Migration requires manual intervention or review (e.g., different module name).
- **BLOCKED**: Known incompatible dependency (e.g., pre-built static framework without SwiftPM support).
- **UNKNOWN**: Dependency not in the registry. Needs manual mapping.

We never guess. We never blindly edit your project files without a plan.

## Installation

PkgLift v0.1.1 and later is distributed as a Developer ID-signed and Apple-notarized
Apple Silicon binary for macOS 14 or later.

Install with Homebrew:

```bash
brew install Alexsvensson99/tap/pkglift
```

Release archives are also available from
[GitHub Releases](https://github.com/Alexsvensson99/PkgLift/releases).
Maintainer signing, notarization, and release instructions are documented in
[Distribution](Documentation/Distribution.md).

Verify and extract a downloaded archive before installing it:

```bash
shasum -a 256 -c pkglift-macos-arm64.tar.gz.sha256
tar -xzf pkglift-macos-arm64.tar.gz
sudo mkdir -p /usr/local/libexec/pkglift /usr/local/bin
sudo cp pkglift /usr/local/libexec/pkglift/
sudo cp -R PkgLift_PkgLiftRegistry.bundle /usr/local/libexec/pkglift/
sudo ln -sf /usr/local/libexec/pkglift/pkglift /usr/local/bin/pkglift
```

From a source checkout:

```bash
swift build -c release
sudo mkdir -p /usr/local/libexec/pkglift /usr/local/bin
sudo cp .build/release/pkglift /usr/local/libexec/pkglift/
sudo cp -R .build/release/PkgLift_PkgLiftRegistry.bundle /usr/local/libexec/pkglift/
sudo ln -sf /usr/local/libexec/pkglift/pkglift /usr/local/bin/pkglift
```

## Quick Start

1. Navigate to your project directory containing the `Podfile` and `.xcodeproj` or `.xcworkspace`.
2. Run `pkglift analyze` to see what dependencies can be migrated.
3. Run `pkglift plan` to generate a `.pkglift/plan.json` file.
4. Review every entry in the plan.
5. Run `pkglift migrate` for a validated dry run.
6. Keep the generated `.pkglift/plan.json` from appearing as an untracked change. For a one-off test, add only that file to the repository-local Git exclude; for a shared policy, add it to `.gitignore` and commit the policy change. See [Testing PkgLift on a Real Project](Documentation/RealWorldTesting.md) for the safe commands and review flow.
7. Confirm that `git status --short` is empty, then run `pkglift migrate --apply`.
8. Run `pod install` so CocoaPods updates the dependencies that remain.
9. Run `pkglift verify`; add `--build --scheme <scheme>` for a full build.

PkgLift deliberately refuses `--apply` when Git reports a dirty worktree. Do not bypass that safeguard to work around the generated plan file.

## Commands

- `analyze`: Scans the project and dependencies.
- `plan`: Generates a migration plan.
- `migrate`: Validates the saved plan and previews it; `--apply` performs only typed `AUTO` actions.
- `verify`: Verifies the build post-migration.
- `registry validate`: Validates the local registry mappings.
- `version`: Prints the current version.

## Registry

The PkgLift Registry is an open-source database mapping CocoaPods to their SwiftPM equivalents. It handles module renaming, version requirements, and compatibility checks.
See [Registry](Documentation/Registry.md) to learn how to contribute!

## Configuration

You can customize PkgLift using a `.pkglift.yml` file in your project root.
```yaml
# .pkglift.yml
schemaVersion: 1
migration:
  allow:
    - Alamofire
  deny:
    - SomeInternalPod
```

An invalid configuration is an error; PkgLift does not silently ignore it.

## Limitations

For v0.1.x:
- Only CocoaPods to SwiftPM migration is supported.
- A stable `major.minor.patch` lockfile version at or above the exact mapping's verified SwiftPM minimum and exactly one matching Xcode target are required for `AUTO`.
- Dynamic Ruby, install hooks, `script_phase`, `use_frameworks!`, `inherit! :search_paths`, `abstract_target`, external pod sources, and ambiguous target mappings are `REVIEW` or `BLOCKED`.
- Base pod mappings never apply automatically to undeclared subspecs.
- PkgLift removes only exact migrated pod declarations. It deliberately preserves target blocks, unrelated Ruby, and CocoaPods integration for pods that remain.
- PkgLift does not run `pod install` automatically.
- Objective-C support is limited to standard SwiftPM integration.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for our long-term vision.

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---
**Note:** PkgLift is an independent open-source project and is not affiliated with Apple Inc. or the CocoaPods organization.
