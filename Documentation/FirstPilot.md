# Your first PkgLift 1.0 pilot

This short pilot stops after a dry run. It helps you see which direct CocoaPods dependencies PkgLift can safely identify in a native Xcode project. A `REVIEW`, `BLOCKED`, or `UNKNOWN` result is useful: it means PkgLift kept an uncertain dependency out of automatic migration.

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

Keep raw plans, logs, source, and private project details local. Portable analysis and plan JSON still contain dependency and target names. `pkglift diagnostics` creates a minimized local report that omits those names, but it must also be reviewed before sharing. See [Diagnostics](Diagnostics.md) for the exact privacy boundary. The [migration report form](https://github.com/Alexsvensson99/PkgLift/issues/new?template=migration_report.yml) is available for a safe public report. A small report is enough:

```text
PkgLift version / macOS / Xcode / Swift / CocoaPods:
Project shape (single project, multi-project workspace, target count):
Baseline build (command and pass/fail, without private output):
Commands run and where the pilot stopped:
Direct dependency counts: AUTO __ / REVIEW __ / BLOCKED __ / UNKNOWN __
Expected result versus observed result (redacted):
Did tracked project content remain unchanged after dry run? Yes / No / Unknown
Smallest safe reproduction or relevant reason codes:
```
