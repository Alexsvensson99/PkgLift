# PkgLift 0.6.1 interrupted-migration validation

Local source preparation on 2026-09-06; no publication or remote workflow was
performed. The patch is based on main commit
`16725744de53d3e0a4dea288b1ad8a8499cd4655` (source version 0.6.0), on branch
`codex/v0.6.1-interrupted-migration`. It was prepared in an isolated checkout;
the pre-existing working tree and its 21 modified files were preserved.

## Root cause and implementation

`AtomicMigration.perform` previously restored files only if its Swift action
threw. Default process signal termination bypassed that catch block, and a later
migration could delete the backup and copy the partially migrated originals over
it.

The existing transaction wrapper now reserves an exclusive, synchronized marker
before preparing the backup. The marker contains only a schema version,
canonical original paths, and the fixed backup location. A completed receipt
binds terminal backups to those originals and their backup location. Marker
presence always wins over a terminal receipt. Unknown or mismatched receipts
fail closed. The marker also excludes a second apply during backup preparation.

A small C target captures SIGINT/SIGTERM using a lock-free atomic flag; it does no
filesystem work in a signal handler. The CLI installs/restores the dispositions
only around apply. The existing synchronous engine checks cancellation around
Podfile and Xcode writes and before commit. Rollback stages copies, attempts
every original, synchronizes restored data, and only then finalizes the receipt
and clears the marker. Unrelated errors are preserved. Incomplete rollback
retains recovery state and reports both the triggering and restoration errors.

This remains a 0.6.1 safety patch: no new public command, new migration strategy,
registry evidence, classification expansion, or generated-package behavior.
Existing dirty-tree, plan-version, project-matching, and preflight checks remain.

## Final local results

Environment: Apple Swift 6.3.3, arm64 macOS; SwiftPM concurrency limited to four
jobs. Build/test caches and configuration directories were kept local.

| Check | Result |
| --- | --- |
| Targeted migration and CLI XCTest suites | 66 passed, 0 failures |
| Full XCTest suite | 291 passed, 0 failures |
| Full Swift Testing suite | 152 passed in 12 suites, 0 failures |
| Full Swift total | 443 passed, 0 failures |
| Debug build | Passed, no compiler warnings |
| Release build | Passed, no compiler warnings |
| Debug and release registry validation | 22 mappings each, passed |
| Release binary version | `0.6.1` |
| Release-manifest policy tests | 26 passed |
| Repository YAML | 14 files, 10 SHA-pinned workflows, 2 issue forms passed |
| C signal helper, `-Wall -Wextra -Werror` | Passed |
| Patch whitespace | `git diff --check` passed |
| Final safety review | No classification/preflight weakening found |

The targeted 66 tests comprise AtomicMigrationTests (10),
CommandContextMigrationTests (18), MigrateInterruptionTests (8),
MigrationEngineTests (5), and MigrationPlanPreflightTests (25).

## Regression coverage

- A normal migration completes, clears the marker, and leaves a terminal backup
  eligible for later reuse for the same originals.
- Existing Swift failures and an actual Xcode editor error restore both originals.
- Real subprocess SIGINT and SIGTERM after Podfile writing and after a package
  addition restore the Podfile and full project tree byte for byte, retain the
  original backups, clear active state, and exit 130/143.
- Real subprocess SIGKILL after Podfile writing leaves the marker and original
  backups intact; the next apply, including `--allow-dirty`, is refused.
- An incomplete marker is detected before reading corrupt plan/project files.
- A second owner, legacy backup, mismatched receipt, and dangling marker symlink
  cannot bypass backup protection.
- A missing required original, pre-mutation cancellation, cancellation during
  backup, and a missing exact Podfile declaration do not create active recovery
  state after successful cleanup.
- Rollback failure still attempts the other original, preserves the marker, and
  refuses subsequent apply.
- Dry run creates no backup or transaction marker. Existing dirty-tree, project,
  classification, and version-bound plan regression suites pass unchanged.

The eight CLI test methods include one normally inert child-process helper. Real
signal tests select this helper in an isolated XCTest process and call `raise`
at a named migration checkpoint; they use no arbitrary sleeps or timing races.
A ten-second timeout bounds a broken test child, not signal delivery timing.

## Reproduction commands

Run in the patch checkout. The path flags avoid writing shared user caches in a
restricted local environment; `--disable-sandbox` applies to SwiftPM's build
subprocess sandbox only.

```bash
swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local -j 4 --filter 'AtomicMigrationTests|MigrationEngineTests|MigrateInterruptionTests|CommandContextMigrationTests|MigrationPlanPreflightTests'
swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local -j 4
swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local -j 4
swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local -c release -j 4
swift run --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local -j 4 pkglift registry validate
.build/release/pkglift version
.build/release/pkglift registry validate
ruby Scripts/validate-repository-yaml.rb
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/ReleaseManifestTests -p 'test_*.py'
clang -std=c11 -Wall -Wextra -Werror -fsyntax-only -I Sources/PkgLiftSignalSupport/include Sources/PkgLiftSignalSupport/Signals.c
git diff --check
```

## Changed files

- `Sources/PkgLiftMigration/AtomicMigration.swift`: marker, backup receipt,
  interruption checkpoints, durable preparation and complete rollback reporting.
- `Sources/PkgLiftMigration/MigrationEngine.swift`: checkpoints around actual writes.
- `Sources/PkgLiftCLI/MigrateCommand.swift`: early recovery refusal and signal scope.
- `Sources/PkgLiftCLI/MigrationSignals.swift`: Swift signal lifetime/error adapter.
- `Sources/PkgLiftSignalSupport/Signals.c` and
  `Sources/PkgLiftSignalSupport/include/PkgLiftSignalSupport.h`: safe signal capture.
- `Package.swift`: internal signal-support target dependency.
- `Sources/PkgLiftCore/Version.swift`: source version 0.6.1.
- `Tests/PkgLiftMigrationTests/AtomicMigrationTests.swift`,
  `Tests/PkgLiftMigrationTests/MigrationEngineTests.swift`, and
  `Tests/PkgLiftCLITests/MigrateInterruptionTests.swift`: regression coverage.
- `CHANGELOG.md`, `Documentation/MigrationSafety.md`,
  `Documentation/ReleaseNotes-0.6.1.md`, and this report: release/recovery guidance.

## Boundaries before publication

Saved plans created by 0.6.0 or any other version must be regenerated with 0.6.1.
After SIGKILL, a process crash, SIGHUP, or power/OS failure, rollback cannot run
after the process is dead. Surviving recovery state is detected and preserved;
this is not a claim that hardware or the filesystem cannot lose synchronized
data. A signal first observed after commit leaves a fully migrated result and is
reported accordingly. Consult [Migration Safety](MigrationSafety.md#rollback-boundary)
before restoring or archiving an incomplete transaction.

Remote CI (including the Xcode mixed-language build pilot), signing,
notarization, publication manifest/artifacts, public tag/GitHub Release, and
Homebrew publication have not been performed for this patch and remain release
gates. No manifest containing invented commit, workflow, or artifact identifiers
was added. This report establishes local patch validation, not distribution
readiness or a published release.
