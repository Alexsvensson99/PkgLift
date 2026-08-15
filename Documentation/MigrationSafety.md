# Migration Safety

PkgLift follows one rule: when information is missing or ambiguous, stop and explain instead of guessing.

## AUTO requirements

An `AUTO` entry requires all of the following:

- an unconditional literal direct pod declaration, with at most a literal version constraint, backed by a valid, verified registry mapping;
- a stable `major.minor.patch` version from the lockfile at or above the mapping's verified SwiftPM minimum;
- a non-empty SwiftPM repository and product list;
- exactly one Podfile destination target and exactly one matching Xcode target;
- no unsupported Podfile control flow, hooks, `script_phase`, `use_frameworks!`, `inherit! :search_paths`, `abstract_target`, or external source;
- no conflicting existing SwiftPM package requirement;
- typed remove, add, and link actions that agree with the plan metadata.

Anything less becomes `REVIEW`, `BLOCKED`, or `UNKNOWN`.

Classification retains every independently applicable reason in a stable order. A dependency can therefore report target ambiguity, dynamic Ruby, install hooks, inheritance, and mapping limitations together instead of hiding later risks behind the first match.

Registry identifiers are exact. Declaring a base pod does not make its transitive subspecs direct dependencies, and a base mapping is never inherited by an arbitrary subspec.

## Declaration and target evidence

PkgLift records every literal Podfile declaration that contributes to an exact pod name. Repeated rows are aggregated without discarding their line, scope, source, or target evidence. Similar base pods and subspecs remain distinct identities.

`AUTO` requires all declaration origins to resolve to the same single literal Xcode target. Parent-target declarations are expanded to statically proven nested targets when CocoaPods default or complete inheritance applies. `inherit! :search_paths` and `inherit! :none` do not inherit the parent's pod declaration. Unknown structure, dynamic target names, unsupported conditions or options, and non-literal helper dispatch produce partial or unresolved evidence and require review.

Only bounded static Ruby helpers are analyzed: calls and supported directives must be literal, and dynamic dispatch marks the affected helper evidence unresolved. PkgLift still never executes the Podfile as Ruby.

## Project and workspace selection

PkgLift discovers `.xcodeproj` and `.xcworkspace` directories recursively beneath
`--path` without descending into generated `Pods`, `.build`, `.swiftpm`,
`Carthage`, or `DerivedData` trees. Project bundles and workspace bundles are
terminal discovery nodes, so internal Xcode metadata is not treated as another
user workspace.

All explicit selections and workspace project references are standardized and
resolved through symlinks before use. They must remain inside `--path`.
Multi-project workspaces require `--workspace` together with `--project`, and the
selected project must be an actual non-Pods reference in that workspace.
Unsupported workspace location schemes are refused instead of guessed.

## Preflight and mutation

`pkglift migrate` is a dry run. `pkglift migrate --apply` validates the entire saved AUTO contract before the first write. It refuses stale project paths, missing Podfile declarations, missing or conflicting versions, and missing or ambiguous targets. Every AUTO entry must carry non-empty literal declaration provenance and explicit exact target attribution that agree with the typed actions.

Older schema-1 plans remain decodable, but legacy target arrays are treated only as partial context. An AUTO entry without current provenance is refused and must be regenerated before migration.

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
