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

A SIGINT or SIGTERM captured after the last migration checkpoint but before
normal signal handlers are restored is no longer discarded. The command returns
130 or 143 and explains when the files were already fully migrated. Existing
migration/rollback errors retain precedence. This does not extend the rollback
boundary beyond terminal commit or change the documented SIGKILL/crash limits.

## Compatibility and release status

The source version is `0.6.2`. Generate migration plans again after upgrading;
plans remain bound to the version that created them. No classification or registry
mapping has been broadened, and there is no new recovery command.

This document describes a locally prepared patch. Public release, signed and
notarized assets, and a Homebrew update require their existing release gates.
No release manifest is created as part of product preparation.
