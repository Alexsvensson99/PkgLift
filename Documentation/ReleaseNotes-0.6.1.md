# PkgLift 0.6.1 — Interrupted migration recovery and rollback hardening

Prepared patch; not published, signed, or notarized by this change.

`pkglift migrate --apply` now handles SIGINT and SIGTERM through synchronous
cancellation checkpoints around migration writes. If interruption is observed
before commit, PkgLift restores the original Podfile and full `.xcodeproj` from
its backup. Successful interruption rollback exits with 130 for SIGINT or 143
for SIGTERM. Normal Swift errors still surface after rollback; a rollback error
is reported separately and preserves the recovery state.

An exclusively created, synchronized `.pkglift/migration-in-progress` marker
protects the fixed `.pkglift/backup` location. A surviving marker refuses the next
apply before plan or project parsing, including with `--allow-dirty`. Only a
completed backup receipt matching the migration context permits backup reuse.
Legacy backups without a valid receipt also require inspection.

SIGKILL, process crashes, SIGHUP, or power loss cannot execute rollback after the
process is dead. PkgLift preserves and detects surviving recovery state; it does
not promise a multi-file operating-system transaction or storage-device survival.
See [Migration Safety](MigrationSafety.md#rollback-boundary) before resolving an
incomplete migration. There is no new public recovery command.

## Compatibility

The source version is `0.6.1`. Regenerate saved plans with this version before
applying: preflight still rejects plans created by a different PkgLift version.
Dirty-tree checks, project matching, preflight, classification, and dry-run
semantics are retained. No additional dependencies become `AUTO`.

## Publication boundary

No `v0.6.1` release manifest is fabricated here. It requires actual reviewed
source and workflow evidence. Remote CI and the mixed-language build pilot,
signing, notarization, release assets, public tag/GitHub Release, and Homebrew
publication remain later release gates. No workflow or publication is triggered
by this local preparation.
