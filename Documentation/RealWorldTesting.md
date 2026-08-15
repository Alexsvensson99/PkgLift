# Testing PkgLift on a Real Project

Real-world testing helps uncover project structures, Podfile patterns, target mappings, and verification cases that synthetic fixtures cannot fully represent. Successful, partial, and unsuccessful migrations are all useful when the result is reproducible and safely reported.

PkgLift changes dependency configuration and Xcode project files. Treat every applied migration as a source-code change that must be reviewed.

## Before You Start

1. Use a disposable clone, a temporary branch, or another recoverable copy of the project.
2. Start with a clean Git worktree and confirm that the baseline project builds.
3. Record the versions of PkgLift, macOS, Xcode, Swift, and CocoaPods.
4. Keep the existing `Podfile`, `Podfile.lock`, workspace, and project files under version control.
5. Know how to run the project's normal build or test command before changing dependency configuration.
6. Do not test an applied migration directly on a release branch or an irreplaceable working copy.

## Recommended Test Flow

### 1. Confirm the baseline

Build or test the project before running PkgLift. A failing baseline cannot prove whether a later failure was introduced by the migration.

### 2. Analyze the project

```bash
pkglift analyze
```

Review the discovered project, targets, dependencies, and classifications. Stop if PkgLift selected the wrong project or if the output does not match the repository structure.

### 3. Generate and inspect the plan

```bash
pkglift plan
```

Open `.pkglift/plan.json` and inspect every entry. In particular, confirm:

- the exact pod or subspec identifier;
- the resolved version from `Podfile.lock`;
- the SwiftPM repository and product;
- the destination Xcode target;
- the `AUTO`, `REVIEW`, `BLOCKED`, or `UNKNOWN` classification;
- the reason attached to anything that is not `AUTO`.

Do not manually change an uncertain entry into an executable migration merely to make the plan proceed.

### 4. Run the dry run

```bash
pkglift migrate
```

A dry run should explain the proposed work without modifying the project. Confirm that `git status --short` and `git diff` remain unchanged.

### 5. Apply only a reviewed plan

```bash
pkglift migrate --apply
```

Apply the plan only after reviewing it and confirming that the worktree is clean. PkgLift executes validated `AUTO` actions and preserves dependencies that require review or lack sufficient evidence.

### 6. Refresh remaining CocoaPods integration

```bash
pod install
```

PkgLift deliberately does not run CocoaPods automatically. Review the resulting lockfile, workspace, and project changes before continuing.

### 7. Verify the result

```bash
pkglift verify
```

For a full build verification, provide the project's scheme:

```bash
pkglift verify --build --scheme <scheme>
```

Also run the project's normal tests or build command when it provides coverage beyond PkgLift's structural verification.

### 8. Review the diff

Inspect the complete Git diff. Confirm that:

- only reviewed dependencies were migrated;
- unrelated Podfile content was preserved;
- remaining CocoaPods dependencies still resolve;
- package products were added to the intended targets;
- no unrelated build settings or project objects changed;
- the final project builds from a clean checkout when practical.

## What Makes a Useful Report

A useful report includes:

- the PkgLift and toolchain versions;
- the project shape, such as a single project or multi-project workspace;
- the commands that were exercised;
- a redacted dependency and classification summary;
- the expected and actual outcome;
- whether analysis and dry run left the worktree unchanged;
- whether structural verification and the final build succeeded;
- the smallest relevant error output;
- a public reproduction when one can be shared safely.

Use the [real-world migration report form](https://github.com/Alexsvensson99/PkgLift/issues/new?template=migration_report.yml) to submit the result.

## Redacting Private Information

Before publishing a report, remove or replace:

- access tokens, API keys, credentials, and environment variables;
- signing identities, provisioning data, team identifiers, and bundle identifiers when sensitive;
- customer, employer, product, repository, target, and developer names that are not public;
- private package URLs and internal dependency names;
- absolute paths containing usernames or internal directory structures;
- proprietary source code and complete private Podfiles.

Use stable placeholders such as `InternalAnalytics`, `/path/to/project`, and `com.example.app` so that the report remains understandable. Include only the smallest section needed to reproduce the behavior.

## Reporting Partial or Failed Migrations

A report is still valuable when PkgLift correctly refuses an unsafe migration, classifies a dependency as `REVIEW`, cannot identify an exact target, or encounters an unsupported Podfile construct. Describe what PkgLift preserved, where the workflow stopped, and what evidence would be needed to support the case safely.

Do not weaken a safety check solely to turn a real-world failure into an automatic migration. Convert recurring findings into focused parser, discovery, registry, migration, verification, or documentation work instead.
