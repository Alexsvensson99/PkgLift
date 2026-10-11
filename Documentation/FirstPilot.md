# Your first PkgLift 1.0 pilot

This short pilot stops after a dry run. It helps you see which direct CocoaPods dependencies PkgLift can safely identify in a native Xcode project. A `REVIEW`, `BLOCKED`, or `UNKNOWN` result is useful: it means PkgLift kept an uncertain dependency out of automatic migration.

## Start with the repository fixture

If you want to see the complete dry-run path before using your own code, install PkgLift and run this command from a source checkout of the PkgLift repository:

```bash
bash Scripts/run-five-minute-fixture.sh
```

The script copies the public `Fixtures/PartialSwift` example into a new temporary Git repository. It runs registry validation, analysis, plan generation, and `migrate` without `--apply`, then verifies the plan did not change and Git has no tracked, staged, or unexpected untracked changes. It does not run CocoaPods, `xcodebuild`, a simulator, or any project of yours. The temporary copy is removed after success; add `--keep` to inspect it or `--pkglift /absolute/path/to/pkglift` to select an executable.

This source-checkout demonstration proves only the bounded fixture behavior. It does not establish that your project, host environment, or dependency set is supported.

## Continue with your project

Use a disposable clone or recoverable branch with a committed `Podfile`, `Podfile.lock`, and Xcode project/workspace. Start with a clean Git worktree and a successful baseline build using your project's normal command. Record its result and your macOS, Xcode, Swift, and CocoaPods versions. If the baseline cannot build, report that limitation and stop before judging migration or build compatibility. The [real-project testing guide](RealWorldTesting.md) covers the fuller baseline and later apply flow.

Check the [verified environment matrix](Environments-1.0.md), then install PkgLift on an Apple Silicon Mac. The package minimum alone does not prove that every macOS or Xcode version is tested. If Homebrew reports a prerequisite problem, record it and stop at installation; do not bypass the check.

```bash
brew install Alexsvensson99/tap/pkglift
pkglift version
```

Record the actual installed version. The command sequence below was checked with the released 1.0.1 binary on a repository-owned fixture. Homebrew installation was verified separately in clean hosted checks; see the [verification record](FirstPilot-1.0.1-Verification.md). The Homebrew formula can advance. After an upgrade, generate a new plan. Work from the directory containing the `Podfile`:

```bash
pkglift registry validate --path .
git status --short
pkglift analyze --path .
```

Confirm that Git status is empty and analysis found the intended project, targets, and direct dependencies. Stop and record any error or unexpected selection. Then create the plan:

```bash
pkglift plan --path .
```

`plan` writes the full executable `.pkglift/plan.json`; inspect its exact pod/version, proposed SwiftPM package/product, target, classification, and reasons. After reviewing the plan, run the preview and compare Git state:

```bash
pkglift migrate --path .                 # dry run; do not add --apply
git diff --exit-code
git diff --cached --exit-code
git status --short
```

The generated plan may appear as an untracked change in the final `git status` even though the dry run did not modify tracked project files. Compare the final status with the initial one and account for the generated plan. If `migrate` reports no `AUTO` entries, a no-op is an expected safe result, not a completed migration.

If discovery finds multiple Xcode projects, supply `--project` on **each** `analyze`, `plan`, and `migrate` command. For a multi-project workspace, supply both selection options on **each** command, using paths beneath `--path`:

```bash
pkglift analyze --path . --workspace Workspaces/Products.xcworkspace --project Projects/App.xcodeproj
pkglift plan --path . --workspace Workspaces/Products.xcworkspace --project Projects/App.xcodeproj
pkglift migrate --path . --workspace Workspaces/Products.xcworkspace --project Projects/App.xcodeproj
```

**Stop here for the first pilot.** Do not run unattended `migrate --apply`. If you later choose to apply a reviewed, eligible plan, follow [Testing PkgLift on a Real Project](RealWorldTesting.md) for clean-worktree handling, CocoaPods refresh, structural/build verification, and complete diff review. PkgLift 1.0's positive evidence covers repository fixtures and one named external single-target partial migration; positive external multi-target/workspace migration is still deferred. Discovery and conservative refusal on those shapes do not establish positive migration support. See the [1.0 compatibility contract](Compatibility-1.0.md) and [environment matrix](Environments-1.0.md) for exact boundaries.

## Pilot feedback

Keep raw plans, logs, source, and private project details local. Portable analysis and plan JSON still contain dependency and target names. `pkglift diagnostics` creates a minimized local report that omits those names, but it must also be reviewed before sharing. See [Diagnostics](Diagnostics.md) for the exact privacy boundary. The short [First Pilot feedback form](https://github.com/Alexsvensson99/PkgLift/issues/new?template=first_pilot_report.yml) asks for five short fields. Use the detailed [migration report form](https://github.com/Alexsvensson99/PkgLift/issues/new?template=migration_report.yml) later for apply, verification, or a fuller reproduction. If the issue form is unavailable, use the same five fields in a new issue:

```text
PkgLift version:
Where did you stop?:
Direct dependency counts: AUTO __ / REVIEW __ / BLOCKED __ / UNKNOWN __
What happened? (redacted; say if you only ran the repository fixture):
Did tracked project content remain unchanged after dry run? Yes / No / Unknown / Not reached
```
