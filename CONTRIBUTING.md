# Contributing to PkgLift

First off, thank you for considering contributing to PkgLift!

## Building Locally

PkgLift is built with standard Swift tooling.

```bash
swift build
```

## Running Tests

```bash
swift test
```

## Adding Registry Mappings

The registry is the heart of PkgLift. If a dependency shows up as `UNKNOWN`, it's because it's not in the registry.

1. Fork the repository and create a branch.
2. Locate the `Registry/` directory.
3. Add a new `.yml` file for the mapping using the documented schema.
4. Validate your mapping:
   ```bash
   swift run pkglift registry validate
   ```
5. Submit a Pull Request.

See [Contributing Mappings](Documentation/ContributingMappings.md) for a detailed step-by-step guide.

## Reporting Bugs

Please use the provided Bug Report template in the `.github/ISSUE_TEMPLATE` directory. Include your `Podfile` (if possible), PkgLift output, and Swift/macOS versions.

## Proposing Features

Please use the provided Feature Request template. Be descriptive about the use case and why it benefits the ecosystem.

## Code Style

PkgLift follows the standard [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/). Please ensure your code is clean, readable, and well-commented.

## PR Process

1. Create a branch named `feature/my-feature` or `bugfix/issue-123`.
2. Ensure tests pass (`swift test`).
3. Ensure registry validation passes (`swift run pkglift registry validate`).
4. Open a PR against `main`.
5. Require at least one review from a maintainer before merging.

## Good First Issues

If you're looking for a place to start, check out issues labeled `good first issue`. These are typically:
- Adding simple registry mappings
- Adding test fixtures
- Minor parser improvements
- Documentation fixes
