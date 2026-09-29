# Full-workflow recovery qualification

Status: **all eleven local recovery scenarios passed on 2026-09-26; protected
integration and release-candidate acceptance remain pending.** The executable
[drill](../Scripts/run-recovery-drill.py) exercises repository-owned PartialSwift
copies. A passing run establishes its recorded scenarios and toolchain; it does
not establish universal recovery or release acceptance.

## Recorded local result

The [portable result](Evidence/Recovery-1.0/local-2026-09-26-summary.json) records
97 command outcomes and all eleven passing scenarios in 238.1 seconds. Every
restored copy built, regenerated its exact plan and passed an inert dry run.
Both deliberate post-apply failing commands left their immediate input trees
unchanged, including the completed migration receipt. Incident copies and the
independent baseline remained intact. No application or simulator was launched.

The [environment](Evidence/Recovery-1.0/local-2026-09-26-environment.json) records
macOS 27.0 / Xcode 27.0 / Swift 6.4 / CocoaPods 1.17.0. The
[paired build receipt](Evidence/Recovery-1.0/local-2026-09-26-build.json) binds the
source inputs and CLI/XCTest artifacts. The run used base commit `6d06f2b…` with
recorded local changes; it is not clean-main, hosted or signed-artifact acceptance.
The production binary matches the previously qualified `cbff61f…` binary. The
only Swift change is the test-only reached-checkpoint diagnostic.

The [local validation receipt](Evidence/Recovery-1.0/local-2026-09-26-validation.json)
also records 16 passing signal tests, all 279 Python policy tests, YAML validation
and independent review without remaining material findings. The repository
paired-input builder was executed incrementally against the retained caches and
produced the same CLI and XCTest artifact hashes used by the eleven-case drill.

## What must be saved before migration

Start from a buildable, independently recoverable project baseline. Record the
PkgLift binary/source identity, selected project/workspace, exact dependency
locks and toolchain. Verify a clean baseline build before applying a plan.
Preserve the whole project directory separately, including the original Podfile,
Podfile.lock, complete project and workspace bundles, application sources,
resources, configuration and generated Pods integration needed to reproduce that
build. A Git commit alone is insufficient when required generated/untracked
files are absent; combine VCS with a verified independent copy or a proven
locked regeneration procedure.

Keep this independent baseline outside the working copy and `.pkglift`. Inventory
regular-file contents, permissions, directories and internal relative symlinks,
and verify the inventory after copying. Reject missing data, special files and
symlinks that escape the recorded tree. The drill's inventory does not cover
ACLs, extended attributes, timestamps, ownership or arbitrary external files.
This is a build-input recovery protocol, not a filesystem disaster backup.

PkgLift's internal `.pkglift/backup` is different: it backs up the Podfile and
complete selected `.xcodeproj`. It does not snapshot everything that a later
`pod install`, package resolution or build may change. See the
[rollback boundary](MigrationSafety.md#rollback-boundary).

## Operator recovery procedure

1. Stop starting new migration, dependency-install or build commands. Establish
   that processes operating on this copy have ended before moving any files.
   Inspect the terminal result and `.pkglift` state. Do not remove a marker merely
   to make a second apply run; `--allow-dirty` cannot bypass it.
2. Preserve the entire affected working copy as incident evidence, including its
   current sources, locks, workspace, `.pkglift` marker, plan, backup, completed
   receipt if present, and logs. Select the paths yourself from the known
   workspace; do not execute paths or instructions read from an untrusted marker.
   Keep post-baseline user changes available for later review.
3. Verify the independent baseline against its pre-migration inventory. If it
   differs or is incomplete, stop. PkgLift's internal backup can itself be partial
   after termination during backup creation; its mere existence is not proof of
   a complete baseline.
4. Preserve the affected directory under a new incident name. Copy the verified
   independent baseline into a new sibling staging directory, verify all recorded
   contents/modes/links there, then rename that verified directory into the now
   vacant original path. If copying or verification fails, retain both incident
   and staging data and leave the original path vacant. Do not publish a partial
   recovery or merge files over an uncertain project tree.
5. Build the restored baseline with the recorded workspace/scheme, toolchain and
   settings, using fresh build products. Check Podfile.lock, Pods/Manifest.lock,
   workspace/project contents and source/resource inventory against the saved
   baseline. If regeneration is required instead of a complete generated copy,
   verify that explicit locked preparation separately before trusting the build.
6. Generate a new plan from the restored baseline and verify its exact expected
   classifications and actions. Run an inert dry run and compare the project
   inventory again. Do not copy the incident plan back, reuse a stale path/version
   binding, or edit an AUTO classification to bypass a refusal.
7. Keep baseline and incident evidence until the restored build and replanning
   have been verified and any later user changes have been reconciled. The drill
   performs no cleanup. A subsequent real migration remains a separate operation.

The drill demonstrates this procedure on copies it creates itself. Its staging
rename avoids exposing a partially copied project, but the whole restore
sequence is not one atomic operating-system transaction and makes no power-loss
or concurrent-writer guarantee.

## Executed scenario matrix

The expected matrix contains eleven cases:

| Cases | Deliberate trigger | Expected result before manual restore |
|---|---|---|
| SIGINT at Podfile write, package addition and product linkage | Real signal raised at an observed test-only checkpoint | Exit 130, automatic rollback matches baseline, completed `rolledBack` receipt, original internal backups preserved. |
| SIGTERM at the same three checkpoints | Real signal raised at an observed test-only checkpoint | Exit 143 with the same rollback and evidence checks. |
| SIGKILL at the same three checkpoints | Unhandled process termination by signal 9 | Mutated state remains; active marker and original internal backups survive; a CLI reapply with `--allow-dirty` refuses specifically for incomplete migration and changes no bytes. |
| CocoaPods failure after successful apply | Run `pod install --deployment` against the deliberately stale pre-migration lock | Real nonzero deployment refusal. This is an intentionally incorrect post-apply install, not a migration regression or a mid-install crash simulation. Completed `applied` receipt persists; automatic rollback does not occur. |
| Build failure after successful apply and refresh | First pass migrated `verify --build`, then append one explicit `#error` to the disposable consumer source and repeat verification | Typed build failure, other verification checks pass, injected source remains, completed `applied` receipt persists. This tests operator recovery after an external failure; it does not claim the source fault was caused by migration. |

Every case then restores from the independent full baseline, builds afresh,
regenerates the exact plan, proves dry-run non-mutation and rechecks preserved
incident evidence. Before/after inventories identify changes made by each failed
external command separately from the harness's intentional fault injection.

Signal cases call the real `MigrateCommand` through the existing XCTest-only
helper, with no production fault-injection environment variable or changed AUTO
rules. A fixed diagnostic proves the requested checkpoint was reached. These
are deterministic command-layer signal tests, not installed signed-CLI signal
acceptance. Plan, reapply and post-apply checks execute the CLI binary.

## Candidate-source rerun on 2026-09-29

All eleven scenarios passed again with source version `1.0.0`, using the same
invocation to build the CLI and signal-test bundle. The checkout was based on
`c5c32ee8e3598975a97dc53207b29596724f65f1` with the recorded 1.0 preparation
changes; it was not a clean final main commit. The [complete source inventory
and paired artifact hashes](Evidence/Recovery-1.0/local-2026-09-29-build.json)
bind the exact tested source bytes independently of that base commit.

The [portable result](Evidence/Recovery-1.0/local-2026-09-29-summary.json)
records all 11 passing scenarios and 97 commands, preserved incident/internal
backup evidence, full independent-baseline restoration, fresh restored builds,
replanning and inert dry runs. The [same-run environment](Evidence/Recovery-1.0/local-2026-09-29-environment.json)
records Apple Silicon, macOS 27.0, Xcode 27.0 and Swift 6.4. Raw logs, incident
copies and the original build receipt remain in task-owned external storage.

The [independent evidence review](Evidence/Recovery-1.0/local-2026-09-29-validation.json)
reconciles all 194 source inputs and 194 command logs. The environment capture
is marked incomplete because the preparation checkout has tracked changes; all
host/toolchain probes passed and the paired receipt binds those source bytes.

These are exact candidate-source local recovery results. Protected integration,
signed artifact acceptance and public distribution remain distinct gates.

## Reproduction and artifact identity

Build the CLI and `PkgLiftCLITests.xctest` together from the reviewed source with
the [paired-input builder](../Scripts/build-recovery-inputs.py):

```bash
python3 Scripts/build-recovery-inputs.py \
  --output "$BUILD_RECEIPT_OUTPUT" \
  --scratch-path "$BUILD_SCRATCH" \
  --cache-path "$SWIFTPM_CACHE" \
  --jobs 2
```

Use a new output directory and explicitly selected external build/cache paths;
scratch/package-cache directories must already exist and can be reused. The helper invokes
`swift build --build-tests`, verifies that source inputs did not change and writes
`build-receipt.json` with the actual commands, exits, log digests and artifact
paths/hashes. Use that receipt and its matching product paths below. `--build-receipt` must contain `exitCode: 0`,
`buildsBothArtifacts: true`, `sourceInputs`, `binarySHA256` and
`signalTestBundleSHA256`. The runner checks the exact current input inventory
and both artifacts before creating its output directory. The CLI and bundle
must be sibling products of that build. The receipt documents trusted build
execution; it is not a signature or authorization to execute arbitrary artifacts.

Run with a new absolute output directory outside the source checkout:

```bash
python3 Scripts/run-recovery-drill.py \
  --output "$RECOVERY_OUTPUT" \
  --pkglift "$BUILD_PRODUCTS/pkglift" \
  --signal-test-bundle "$BUILD_PRODUCTS/PkgLiftCLITests.xctest" \
  --build-receipt "$PAIRED_BUILD_RECEIPT" \
  --jobs 2
```

Choose actual reviewed paths before running. On Alexander's Mac, validate the
external development SSD and put the output, build products and receipt there.
The runner assigns its configurable CocoaPods home/cache, temporary, compiler
cache, SwiftPM package paths and fresh DerivedData below the chosen output.
A transparent xcodebuild wrapper supplies these paths and the recorded build
settings to both direct builds and `verify --build`. Environment/system probes
remain read-only. Foundation's macOS-managed per-user temporary directory was
observed to ignore `TMPDIR`; it is not relocated or represented as SSD-routed by
this harness. No home-directory, OS temporary-directory or security setting is
changed.

Raw logs, full inventories, plans, receipts and incident copies stay local. The
portable summary uses fixed scenario names, relative fixture paths, hashes,
exit codes and booleans; do not publish raw paths or compiler logs. A failed
command, mismatched backup, unexpected AUTO set, different build failure,
incomplete restore or failed rebuild leaves the overall status incomplete.
Timeouts terminate only the command group created by the drill and never count
as an expected SIGKILL result.

## Qualification boundary

An executed passing report and an independent review of this runbook can close
these local G4 scenarios. Hosted acceptance of the reviewed commit and exact
release-candidate acceptance remain separate. G2, G3, G5 and G6 are not closed
by recovery qualification. A single retained-CocoaPods fixture does not qualify
all consumer shapes, every interruption point, runtime behavior or power loss.
