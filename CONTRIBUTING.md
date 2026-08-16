# Contributing to PkgLift

Thank you for considering a contribution to PkgLift. Contributions should make CocoaPods-to-SwiftPM migration safer, clearer, or more broadly useful without weakening the evidence required for automatic changes.

## Choose a Contribution Path

You can help by:

- testing PkgLift on a recoverable copy of a real project;
- reporting a reproducible bug or unsupported project pattern;
- proposing a verified registry mapping;
- adding focused fixtures or regression tests;
- improving parser, discovery, migration, verification, or documentation behavior.

For approachable tasks, look for issues labeled `good first issue` or `help wanted`.

## Building Locally

PkgLift is built with standard Swift tooling:

```bash
swift build
swift build -c release
```

## Running Validation

Run the test suite:

```bash
swift test
```

Validate every registry entry:

```bash
swift run pkglift registry validate
```

Validate repository workflows and issue forms:

```bash
ruby Scripts/validate-repository-yaml.rb
```

Registry-related pull requests must pass both the test suite and registry validation. Other changes should still run registry validation when they can affect loading, classification, planning, migration, or release packaging.

Pull requests run independent Build, Test, Quality, CodeQL, Registry Gate, Pinned Pilot Gate, and Mixed-Language Pilot Gate checks. The stable gates are always visible; expensive registry, scan, and pilot work runs only when its owned paths changed. Validation workflows use least-privilege permissions, full commit SHA-pinned Actions, and may cancel an older run when a newer commit replaces it on the same pull request.

## Testing on a Real Project

Read [Testing PkgLift on a Real Project](Documentation/RealWorldTesting.md) before applying a migration. Use a clean Git worktree, disposable branch, or recoverable copy; establish a successful baseline build; inspect the generated plan; and review the complete diff afterward.

Submit successful, partial, and unsuccessful results through the [real-world migration report form](https://github.com/Alexsvensson99/PkgLift/issues/new?template=migration_report.yml). Remove secrets, private identifiers, proprietary code, and unnecessary project details before publishing.

## Adding Registry Mappings

The registry maps exact CocoaPods identifiers to verified SwiftPM repositories and products. If a dependency appears as `UNKNOWN`, PkgLift does not have enough exact evidence to map it automatically.

1. Verify the official upstream repository and podspec.
2. Verify the exact pod or subspec identifier.
3. Verify the exact product exported by a tagged `Package.swift` manifest.
4. Verify every consumer source language claimed by the mapping using official guidance or a reproducible compiling fixture.
5. Identify a conservative stable `major.minor.patch` version where that product and language support exist.
6. Copy `Registry/_template.yml` into the matching alphabetical folder.
7. Add the same mapping to the bundled registry resource when required by the repository structure.
8. Run registry validation and the full test suite.
9. Include upstream evidence in the pull request description.

See [Contributing Registry Mappings](Documentation/ContributingMappings.md) for the detailed rules. A mapping can also be proposed through the [registry mapping form](https://github.com/Alexsvensson99/PkgLift/issues/new?template=registry_mapping_request.yml).

Do not guess repository URLs, products, versions, module names, subspec behavior, consumer-language support, or compatibility. A package implemented in Swift is not automatically safe to consume from Objective-C. Incomplete evidence should remain review-only rather than becoming `AUTO`.

## Reporting Bugs

Use the Bug Report template for a defect in PkgLift itself. Include:

- the PkgLift, macOS, Xcode, Swift, and CocoaPods versions;
- the smallest reproducible Podfile or fixture you are authorized to share;
- the command that failed;
- the expected and actual behavior;
- redacted output and a minimal reproduction when available.

Use the real-world migration report form instead when the main purpose is to describe the outcome of testing an existing project.

## Proposing Features

Use the Feature Request template. Describe the concrete developer problem, the project structures or workflows affected, the safety implications, and the smallest useful outcome. Prefer evidence from reproducible cases over speculative breadth.

## Code Style and Safety

PkgLift follows the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/). Keep changes focused, readable, type-safe, and testable.

Preserve these invariants:

- never classify a dependency as `AUTO` without exact evidence;
- require a complete PBX source profile and explicit registry support for every consumer target language before `AUTO`;
- treat detected Carthage, React Native, Flutter, and Capacitor integration as a project-level automatic-migration boundary;
- never weaken a safety check merely to make a fixture pass;
- use typed errors instead of traps or forced assumptions;
- keep analysis and dry-run paths mutation-free;
- preserve unrelated Podfile and Xcode project content;
- route project-file mutations through the existing migration and Xcode modules.

See [AGENTS.md](AGENTS.md) for repository-specific guidance that also applies when coding agents assist with a contribution.

## Pull Request Process

1. Create a focused branch such as `feature/my-feature` or `bugfix/issue-123`.
2. Add or update tests that prove the intended behavior and relevant safety boundaries.
3. Run `swift build` and `swift build -c release`.
4. Run `swift test`.
5. Run `swift run pkglift registry validate` when applicable.
6. Run `ruby Scripts/validate-repository-yaml.rb` when workflows or issue forms change.
7. Review `git diff --check` and the complete patch.
8. Open a pull request against `main` using the repository template.
9. Explain the user problem, implementation, safety impact, and validation performed.
10. Address review feedback and keep unrelated changes out of the pull request.
