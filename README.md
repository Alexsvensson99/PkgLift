# PkgLift

[![Build](https://github.com/Alexsvensson99/PkgLift/actions/workflows/build.yml/badge.svg)](https://github.com/Alexsvensson99/PkgLift/actions/workflows/build.yml)
[![Test](https://github.com/Alexsvensson99/PkgLift/actions/workflows/test.yml/badge.svg)](https://github.com/Alexsvensson99/PkgLift/actions/workflows/test.yml)
[![Quality](https://github.com/Alexsvensson99/PkgLift/actions/workflows/quality.yml/badge.svg)](https://github.com/Alexsvensson99/PkgLift/actions/workflows/quality.yml)
[![CodeQL](https://github.com/Alexsvensson99/PkgLift/actions/workflows/codeql.yml/badge.svg)](https://github.com/Alexsvensson99/PkgLift/actions/workflows/codeql.yml)
[![Registry Validation](https://github.com/Alexsvensson99/PkgLift/actions/workflows/registry.yml/badge.svg)](https://github.com/Alexsvensson99/PkgLift/actions/workflows/registry.yml)
[![Mixed-Language End-to-End Pilot](https://github.com/Alexsvensson99/PkgLift/actions/workflows/positive-e2e.yml/badge.svg)](https://github.com/Alexsvensson99/PkgLift/actions/workflows/positive-e2e.yml)
[![Latest Release](https://img.shields.io/github/v/release/Alexsvensson99/PkgLift)](https://github.com/Alexsvensson99/PkgLift/releases/latest)
[![License: MIT](https://img.shields.io/github/license/Alexsvensson99/PkgLift)](LICENSE)
[![Website](https://img.shields.io/badge/website-live-0a7b83)](https://www.svensson.design/PkgLift/)

**Modernize Apple dependencies safely.**

PkgLift analyzes native Xcode projects, builds a dependency migration plan, and safely moves the supported subset of CocoaPods dependencies to Swift Package Manager.

No blind conversions. No guesswork.

**Analyze → Plan → Migrate → Verify**

[Project website](https://www.svensson.design/PkgLift/) · [Installation](#installation) · [Quick Start](#quick-start) · [Compatibility](#compatibility) · [Safety Philosophy](#safety-philosophy) · [Diagnostics](Documentation/Diagnostics.md) · [Real-Project Pilots](Documentation/Pilots.md) · [Support](SUPPORT.md) · [Report a Migration](https://github.com/Alexsvensson99/PkgLift/issues/new?template=migration_report.yml) · [Propose a Registry Mapping](https://github.com/Alexsvensson99/PkgLift/issues/new?template=registry_mapping_request.yml)

## What PkgLift Does

PkgLift automates the evidence-backed parts of moving a native iOS or macOS Xcode project from CocoaPods to Swift Package Manager (SwiftPM), while preserving uncertain dependencies under CocoaPods for human review.

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

## A Reviewed Migration, Not a Conversion Guess

A project might begin with direct CocoaPods declarations such as:

```ruby
target 'MyApp' do
  pod 'Alamofire', '5.9.1'
  pod 'InternalAnalytics'
end
```

PkgLift can produce a plan where the exact, version-supported Alamofire mapping is executable while the unknown internal dependency is preserved:

```text
Alamofire 5.9.1      AUTO     exact verified mapping
InternalAnalytics   UNKNOWN  no registry evidence
```

After review, only the `AUTO` entry may be added as a Swift package. The unknown pod and the remaining CocoaPods integration stay in place. PkgLift does not invent a package URL, product name, target, or compatible version.

## Why PkgLift Exists

CocoaPods has [announced a plan for trunk to stop accepting new Podspecs on December 2, 2026](https://blog.cocoapods.org/CocoaPods-Specs-Repo/). The plan explicitly keeps existing trunk and CDN builds available, and does not mean CocoaPods itself or private spec repositories stop working. PkgLift provides a reviewable path for native Xcode projects that want to move supported dependencies to SwiftPM without pretending every pod or project shape can be converted automatically.

## Preparing v0.2.1

- Xcode targets are profiled deterministically from PBX metadata as Swift, Objective-C, Objective-C++, C, or C++ without reading source contents.
- `AUTO` requires a complete target language profile and registry evidence for every consumer language; mixed Swift/Objective-C targets require both.
- Carthage and typed React Native, Flutter, and Capacitor integration evidence prevent automatic migration instead of being inferred away.
- `analyze --portable-json` and `plan --portable-json` redact local paths and URL credentials for reviewable, portable output.
- Seven immutable upstream pilots remain read-only, while a repository-owned mixed-language fixture is the only end-to-end target that may be migrated.

See the [unreleased changelog](CHANGELOG.md), [migration-safety guide](Documentation/MigrationSafety.md), and [real-project pilot documentation](Documentation/Pilots.md) for the complete evidence.

## Safety Philosophy

PkgLift operates on a strict safety model. Every dependency is classified before migration:

| Classification | Meaning | Executed automatically |
|---|---|---:|
| **AUTO** | Exact pod or subspec mapping, supported locked version, verified package product, exact destination target, and complete supported consumer-language evidence | Yes, after plan review and `--apply` |
| **REVIEW** | A plausible migration exists, but human judgment or unsupported project context is involved | No |
| **BLOCKED** | A known incompatibility or unsafe project construct prevents automatic migration | No |
| **UNKNOWN** | PkgLift lacks exact registry evidence | No |

`REVIEW`, `BLOCKED`, and `UNKNOWN` are not failed conversions. They are safe outcomes that prevent PkgLift from changing a project without sufficient evidence.

We never guess. We never blindly edit project files without a reviewed plan.

## Compatibility

PkgLift targets partial CocoaPods-to-SwiftPM migration in native Xcode projects. A language or ecosystem listed as detected is not necessarily eligible for automatic migration.

| Project or integration | Current behavior |
|---|---|
| Swift-only target | `AUTO`-eligible when the complete target profile and exact registry mapping both support Swift |
| Objective-C-only target | `AUTO`-eligible only when the exact mapping explicitly supports Objective-C |
| Mixed Swift/Objective-C target | `AUTO`-eligible only when the same mapping explicitly supports both languages |
| Objective-C++, C, or C++ target | Detected from PBX metadata; currently `REVIEW` unless a mapping explicitly supports every detected language |
| Carthage | Root metadata and confirmed Xcode integration are detected; Carthage dependencies are not parsed, migrated, or modified, and confirmed presence prevents `AUTO` |
| React Native | `use_react_native!` is detected as an unsupported project integration and prevents `AUTO` |
| Flutter | `flutter_install_all_ios_pods` is detected as an unsupported project integration and prevents `AUTO` |
| Capacitor | `capacitor_pods` is detected as an unsupported project integration and prevents `AUTO` |
| Kotlin Multiplatform (KMP) | No heuristic detection is claimed; local pods and dynamic generation remain non-automatic under existing safety rules |

Host support remains macOS 14 or later on Apple Silicon (`arm64`). Distribution is through a Developer ID-signed and Apple-notarized binary, Homebrew, or a source build. See [Limitations](#limitations) for the intentionally conservative boundaries.

## Installation

PkgLift v0.2.0 is distributed as a Developer ID-signed and Apple-notarized Apple Silicon binary for macOS 14 or later.

Install with Homebrew:

```bash
brew install Alexsvensson99/tap/pkglift
```

Release archives are also available from [GitHub Releases](https://github.com/Alexsvensson99/PkgLift/releases). Maintainer signing, notarization, and release instructions are documented in [Distribution](Documentation/Distribution.md).

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

1. Navigate to the repository root containing the `Podfile`; Xcode projects and workspaces may be nested beneath it.
2. Run `pkglift analyze` to see what PkgLift can classify.
3. Run `pkglift plan` to generate `.pkglift/plan.json`.
4. Review every entry in the plan.
5. Run `pkglift migrate` for a validated dry run.
6. Keep the generated `.pkglift/plan.json` from appearing as an untracked change. For a one-off test, add only that file to the repository-local Git exclude; for a shared policy, add it to `.gitignore` and commit the policy change. See [Testing PkgLift on a Real Project](Documentation/RealWorldTesting.md) for the safe commands and review flow.
7. Confirm that `git status --short` is empty, then run `pkglift migrate --apply`.
8. Run `pod install` so CocoaPods updates the dependencies that remain.
9. Run `pkglift verify`; add `--build --scheme <scheme>` for a full build.

PkgLift deliberately refuses `--apply` when Git reports a dirty worktree. Do not bypass that safeguard to work around the generated plan file.

PkgLift discovers projects and workspaces recursively while excluding generated dependency and build trees. If a workspace references multiple projects, select both the workspace and project explicitly:

```bash
pkglift analyze --path . \
  --workspace Workspaces/Products.xcworkspace \
  --project Projects/App.xcodeproj
```

Selection paths are standardized and resolved through symlinks beneath `--path`. Workspace references that escape that root or use unsupported location schemes are refused rather than guessed.

For a reproducible full build, pass the same explicit settings used by the project or CI:

```bash
pkglift verify \
  --path . \
  --workspace MyApp.xcworkspace \
  --project MyApp.xcodeproj \
  --build \
  --scheme MyApp \
  --configuration Debug \
  --destination 'generic/platform=iOS Simulator' \
  --derived-data-path .pkglift/DerivedData
```

## Commands

- `analyze`: Scans the project and dependencies.
- `plan`: Generates a migration plan.
- `migrate`: Validates the saved plan and previews it; `--apply` performs only typed `AUTO` actions.
- `verify`: Verifies the project after migration and can optionally resolve packages and run a build.
- `diagnostics`: Writes a local, privacy-preserving JSON report without uploading it.
- `registry validate`: Validates local and bundled registry mappings.
- `version`: Prints the current version.

`analyze` and `plan` accept `--portable-json` as an alternative to `--json`. Portable output removes local paths and URL credentials and adds `portableOutput.version = 1`, but still contains dependency and target names. `plan --portable-json` prints the redacted representation while keeping the full executable plan in `.pkglift/plan.json`.

## Share a Real-World Result

Testing on varied public and private project layouts helps PkgLift improve without weakening its safety model.

Generate a minimized report when it helps reproduce the result:

```bash
pkglift diagnostics \
  --path . \
  --output pkglift-diagnostics.json
```

Review the JSON before sharing it. The report contains counts, flags, tool versions, Git state, and typed failure stages; it excludes source code, complete Podfiles, dependency and target names, repository URLs, changed filenames, arbitrary error messages, and absolute user paths. See [Privacy-Preserving Diagnostics](Documentation/Diagnostics.md).

- Use the [real-world migration report](https://github.com/Alexsvensson99/PkgLift/issues/new?template=migration_report.yml) for successful, partial, and intentionally refused migrations.
- Use the [registry mapping proposal](https://github.com/Alexsvensson99/PkgLift/issues/new?template=registry_mapping_request.yml) when an exact CocoaPods-to-SwiftPM mapping can be supported by official upstream evidence.
- Read [Testing PkgLift on a Real Project](Documentation/RealWorldTesting.md) before applying changes, and remove private or proprietary information before publishing a report.

## Registry

The PkgLift Registry is an open-source database mapping exact CocoaPods identifiers to verified SwiftPM repositories and products. It handles module naming, version requirements, and compatibility evidence.

See [Registry](Documentation/Registry.md) and [Contributing Registry Mappings](Documentation/ContributingMappings.md) to learn how mappings are verified.

## Configuration

Customize PkgLift using a `.pkglift.yml` file in the project root:

```yaml
schemaVersion: 1
migration:
  allow:
    - Alamofire
  deny:
    - SomeInternalPod
```

An invalid configuration is an error; PkgLift does not silently ignore it.

## Limitations

For the current v0.2.x line:

- Only CocoaPods-to-SwiftPM migration is supported.
- Migration is partial: non-automatic pods and their CocoaPods integration are preserved.
- A stable `major.minor.patch` lockfile version at or above the exact mapping's verified SwiftPM minimum, exactly one matching Xcode target, a complete non-empty target language profile, and mapping support for every detected language are required for `AUTO`.
- Dynamic Ruby, install hooks, `script_phase`, `use_frameworks!`, `inherit! :search_paths`, `abstract_target`, external pod sources, and ambiguous target mappings are `REVIEW` or `BLOCKED`.
- Confirmed Carthage integration and React Native, Flutter, or Capacitor Podfile markers prevent `AUTO`; PkgLift does not migrate or remove those integrations.
- KMP is not detected through speculative file or name heuristics.
- Base pod mappings never apply automatically to undeclared subspecs.
- Project and workspace selection never follows a reference outside `--path`; widen `--path` explicitly if a legitimate workspace spans a broader repository root.
- PkgLift removes only exact migrated pod declarations. It deliberately preserves target blocks, unrelated Ruby, and CocoaPods integration for pods that remain.
- PkgLift does not run `pod install` automatically.
- Objective-C and mixed targets are automatic only for mappings with explicit matching consumer-language evidence. Current bundled C-family coverage is intentionally limited.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for future work and the [v0.2.0 release tracker](https://github.com/Alexsvensson99/PkgLift/issues/26) for the previous release evidence.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) to get started and [SUPPORT.md](SUPPORT.md) to choose the correct support or reporting path.

## License

PkgLift is licensed under the MIT License. See [LICENSE](LICENSE).

---

**Note:** PkgLift is an independent open-source project and is not affiliated with Apple Inc. or the CocoaPods organization.
