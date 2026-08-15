# Reproducible Build Verification

`pkglift verify` always performs structural checks. Add `--build` and an explicit scheme when PkgLift should also resolve Swift packages and run `xcodebuild`.

```bash
pkglift verify --build --scheme MyApp
```

PkgLift does not guess a scheme. Build-specific options are rejected unless `--build` is present.

## Explicit Build Settings

Use the same settings that the project or CI normally uses:

```bash
pkglift verify \
  --build \
  --scheme MyApp \
  --configuration Debug \
  --destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  --sdk iphonesimulator \
  --derived-data-path .pkglift/DerivedData
```

Available options:

| Option | Purpose |
|---|---|
| `--scheme` | Selects the shared scheme used for package resolution and the build. Required with `--build`. |
| `--configuration` | Selects an Xcode build configuration such as `Debug` or `Release`. |
| `--destination` | Passes an explicit destination string to `xcodebuild`. |
| `--sdk` | Selects an SDK such as `iphonesimulator`. |
| `--derived-data-path` | Selects a derived-data directory. Relative paths are resolved beneath `--path`. |

The project or workspace can still be selected explicitly:

```bash
pkglift verify \
  --path . \
  --workspace Workspaces/Products.xcworkspace \
  --project Projects/App.xcodeproj \
  --build \
  --scheme App \
  --configuration Release \
  --destination 'generic/platform=iOS Simulator'
```

## Execution Order

When build verification is requested, PkgLift:

1. validates the scheme and every option before launching `xcodebuild`;
2. performs structural verification;
3. resolves Swift package dependencies with the selected project or workspace and scheme;
4. runs the selected build;
5. combines every check into the final verification result.

The validated scheme and `--derived-data-path`, when provided, are passed to the package-resolution phase. Configuration, destination, and SDK are build-only settings.

PkgLift requires a scheme for workspace package resolution and whenever an explicit derived-data path is used. This fails before launching `xcodebuild` rather than relying on Xcode to infer a scheme differently across project layouts or versions.

## JSON Output and Redaction

Add `--json` for automation:

```bash
pkglift verify \
  --build \
  --scheme MyApp \
  --configuration Debug \
  --derived-data-path /private/path/DerivedData \
  --json
```

The verification checks record that a scheme was provided and show the effective configuration, destination, and SDK. The derived-data path is represented as `<provided>` rather than exposing the absolute path.

Review the complete JSON before publishing it. Build errors can still contain output produced by Xcode or the project toolchain.

## Security Properties

- Every value is passed to `Process` as a separate argument; PkgLift does not construct a shell command.
- Empty values and control characters are rejected before `xcodebuild` starts.
- Build options do not edit project build settings.
- A relative derived-data path is resolved from the explicit `--path`, not from an inferred project location.
- PkgLift continues to require an explicit project or workspace selection when discovery is ambiguous.
- The same validated scheme is used for workspace package resolution and the final build.

## CI Example

A CI job can use a generic destination instead of a named simulator when the project supports it:

```bash
pkglift verify \
  --path . \
  --workspace MyApp.xcworkspace \
  --project MyApp.xcodeproj \
  --build \
  --scheme MyApp \
  --configuration Debug \
  --destination 'generic/platform=iOS Simulator' \
  --derived-data-path "$RUNNER_TEMP/PkgLiftDerivedData"
```

Choose a destination and configuration that already produce a valid baseline build. PkgLift cannot distinguish a migration regression from a project that failed before migration unless the baseline is known.
