# PkgLift 0.6.2 — Migration completion and verification fixes

This patch corrects cases where a migration could leave a supported Podfile
entry behind while reporting success, and where recovery backups interfered
with later project discovery.

## Podfile consistency

Analysis, Podfile editing and structural verification now use the same parser
for declaration evidence. Supported `pod 'Name'`, `pod('Name')` and tab-separated
forms are handled consistently, including repeated declarations of the same pod.
Comments, Ruby data sections and untouched line endings are preserved.

Migration checks the actual written Podfile before finalizing its transaction.
If a migrated declaration remains, or unsupported Ruby makes removal impossible
to establish, the check fails and follows the normal rollback path. Verification
also refuses to report success when it cannot establish removal.

## Recovery copies and project discovery

Automatic project/workspace discovery skips PkgLift's `.pkglift` directory.
A completed backup is therefore not mistaken for a second project by `analyze`
or `verify`. The separate incomplete-migration marker check continues to refuse
another apply when recovery state remains.

## Signals at completion

Signal completion now uses an atomic terminal outcome. A signal recorded before
closure returns 130 or 143 through the normal CLI path. A handler delayed on
another thread until after successful closure exits with the same conventional
status directly, without depending on another Swift flag check. Concurrent late
signals use the first terminal signal's status. This direct path may omit the
detailed interruption message.

Existing migration, rollback and signal-restoration errors retain precedence.
The late-exit path is armed only after successful migration and restoration of
both previous signal dispositions. Ownership is one-shot per CLI process to
prevent delayed handlers from affecting a later installation. Separate CLI
invocations continue to work normally. This does not extend rollback beyond
terminal commit or change the documented SIGKILL/crash limits.

## Compatibility and release status

The source version is `0.6.2`. Generate migration plans again after upgrading;
plans remain bound to the version that created them. No classification or registry
mapping has been broadened, and there is no new recovery command.

The product changes are merged and verified. Signed and notarized distribution
assets, public release, and a Homebrew update remain subject to the existing
release gates. No release manifest is included in product preparation.
