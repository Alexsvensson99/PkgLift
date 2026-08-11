# Migration Safety

PkgLift follows one rule: when information is missing or ambiguous, stop and explain instead of guessing.

## AUTO requirements

An `AUTO` entry requires all of the following:

- an exact direct pod declaration backed by a valid, verified registry mapping;
- a representable semantic version from the lockfile;
- a non-empty SwiftPM repository and product list;
- exactly one Podfile destination target and exactly one matching Xcode target;
- no unsupported Podfile control flow, hooks, `use_frameworks!`, or external source;
- no conflicting existing SwiftPM package requirement;
- typed remove, add, and link actions that agree with the plan metadata.

Anything less becomes `REVIEW`, `BLOCKED`, or `UNKNOWN`.

## Preflight and mutation

`pkglift migrate` is a dry run. `pkglift migrate --apply` validates the entire saved AUTO contract before the first write. It refuses stale project paths, missing Podfile declarations, missing or conflicting versions, and missing or ambiguous targets.

Podfile editing removes only exact, literal pod declarations. Target blocks, similarly named pods, remaining CocoaPods dependencies, comments, and unrelated Ruby are preserved. PkgLift does not run the Podfile as Ruby.

Package references and product links are de-duplicated. Equivalent repository URLs with an optional `.git` suffix or trailing slash resolve to the same identity. Existing requirements are preserved; a conflict stops migration.

## Git behavior

- Git repository, clean: migration may proceed.
- Git repository, dirty: `--apply` refuses by default; `--allow-dirty` is an explicit override.
- Not a Git repository: migration is allowed. Git is recommended, not mandatory.
- Unexpected `git status` failure: migration refuses because safety could not be established.

## Rollback boundary

Before applying changes, PkgLift backs up the Podfile and complete `.xcodeproj` directory under `.pkglift/backup`. If a write or Xcode edit fails during that operation, both are restored.

Rollback does not extend past a successful `migrate --apply`: `pod install` and `verify` are separate, explicit steps. PkgLift does not currently offer an automatic rollback command after verification.
