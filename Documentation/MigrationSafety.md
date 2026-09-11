# Migration Safety

PkgLift follows one rule: when information is missing or ambiguous, stop and explain instead of guessing.

## AUTO requirements

An `AUTO` entry requires all of the following:

- an unconditional literal direct pod declaration, with at most a literal version constraint and the supported static CocoaPods-only option `modular_headers: true`, backed by a valid, verified registry mapping;
- a stable `major.minor.patch` version from the lockfile at or above the mapping's verified SwiftPM minimum;
- a non-empty SwiftPM repository and product list;
- exactly one Podfile destination target and exactly one matching Xcode target;
- a complete, non-empty source-language profile for that target, built only from PBX metadata;
- registry support for every detected target language;
- no unsupported Podfile control flow, hooks, `script_phase`, `use_frameworks!`, `inherit! :search_paths`, `abstract_target`, or external source;
- no confirmed Carthage, React Native, Flutter, or Capacitor project integration;
- no conflicting existing SwiftPM package requirement;
- typed remove, add, and link actions that agree with the plan metadata.

Anything less becomes `REVIEW`, `BLOCKED`, or `UNKNOWN`.

Classification retains every independently applicable reason in a stable order. A dependency can therefore report target ambiguity, dynamic Ruby, install hooks, inheritance, and mapping limitations together instead of hiding later risks behind the first match.

Registry identifiers are exact. Declaring a base pod does not make its transitive subspecs direct dependencies, and a base mapping is never inherited by an arbitrary subspec.

## Declaration and target evidence

PkgLift records every literal Podfile declaration that contributes to an exact pod name. Repeated rows are aggregated without discarding their line, scope, source, or target evidence. Similar base pods and subspecs remain distinct identities.

`AUTO` requires all declaration origins to resolve to the same single literal Xcode target. Parent-target declarations are expanded to statically proven nested targets when CocoaPods default or complete inheritance applies. `inherit! :search_paths` and `inherit! :none` do not inherit the parent's pod declaration. Literal `target('App') do` and `pod('Name')` calls use the same evidence rules as their whitespace forms, including bounded literal version and `modular_headers: true` arguments. Interpolation, variables, external or extra options, expression tails, postfix conditions, semicolons, raw control characters, non-ASCII whitespace, excessive scope nesting, multiline literals or continuations, unrecognized executable statements, helpers that shadow modeled CocoaPods DSL methods, unsupported enclosing blocks or heredocs, unbalanced calls or scopes, unknown structure, dynamic target names, and non-literal helper dispatch produce partial, unresolved, or unrepresentable evidence and require review. Non-executable Ruby block comments and content after `__END__` are ignored only when their markers begin at Ruby-valid physical column zero; indented lookalikes fail closed.

Only bounded static Ruby helpers are analyzed: calls and supported directives must be literal, and dynamic dispatch marks the affected helper evidence unresolved. PkgLift still never executes the Podfile as Ruby.

## External Git source provenance

PkgLift 0.4.0 recognizes one literal `:git` URL with at most one literal `:branch`, `:tag`, or `:commit` in bounded parenthesized or whitespace Podfile forms. Hash-rocket and keyword option syntax are accepted. Variables, interpolation, duplicate Git keys, multiple references, `:git` combined with a version or `:path`, extra options, multiline declarations, semicolons, expression tails, and malformed calls are unsupported. PkgLift does not execute Ruby or contact the repository to fill gaps.

Repository evidence is canonicalized at the parser trust boundary. HTTPS identities remain distinct from SSH identities. Supported SSH URLs must explicitly use the structural `git` user, and SCP-style input must use relative `git@host:owner/repo.git` syntax; those forms share an SSH identity. Missing or different SSH users and absolute SCP paths are not assumed equivalent. Host case, one exact lowercase `.git` transport suffix, and trailing slashes are normalized while repository path case remains significant. Repeated or slash-separated lowercase `.git` suffixes are rejected, and uppercase or mixed-case suffixes remain part of that case-sensitive path. Unsupported schemes, unusual ports, ambiguous paths, traversal-like paths, and unsafe encoded delimiters fail closed.

Branch, tag, and commit literals are accepted only as at most 255 UTF-8 bytes of printable ASCII without whitespace. Commit identifiers must additionally be 7 to 64 ASCII hexadecimal bytes; immutable checkout evidence requires the complete 40- or 64-byte form. This bounded subset makes provenance comparisons byte-exact and deterministic.

Credentials, URL user information, passwords, queries, and fragments are detected and removed before dependency or provenance values are constructed. The original literal is not retained. This guarantee applies to standard analysis and plan JSON as well as portable JSON; an unsafe URL without a defensible canonical identity becomes `<redacted-url>`.

PkgLift combines Podfile declarations with CocoaPods lockfile `EXTERNAL SOURCES` and `CHECKOUT OPTIONS` evidence and derives one of these statuses:

- `supportedImmutable`: repository and reference evidence agrees; a tag has a full checkout commit, or a full declared commit exactly equals the full checkout commit;
- `mutable`: the declaration uses a branch;
- `unpinned`: the declaration has no reference;
- `credentialBearing`, `incomplete`, `conflicting`, `ambiguousRepository`, `unsupportedURL`, or `unsupportedSyntax`: the corresponding trust, completeness, agreement, identity, URL, or grammar requirement failed.

No status authorizes migration. Every external source remains `REVIEW`, `BLOCKED`, or `UNKNOWN`, never `AUTO`, even when immutable provenance is complete and a registry mapping exists. Local `:path` provenance, repository network resolution, Podspec generation, and automatic external-source migration are outside this tranche.

## Consumer-language evidence

PkgLift profiles compiled source types from the Xcode project graph without opening source files. Supported profile values are `swift`, `objectiveC`, `objectiveCPlusPlus`, `c`, and `cPlusPlus`. Missing file references, unknown compiled file types, and file-system-synchronized root groups make the profile incomplete.

A Swift-only target needs a mapping that supports Swift. An Objective-C-only target needs Objective-C support. A mixed target needs every language in the same mapping; supporting only one side is not enough. Empty, incomplete, missing, or changed language evidence forces review or causes migration preflight to refuse the saved plan. The bundled registry currently has no C-family mapping coverage beyond explicitly listed language values, so such targets remain non-automatic unless concrete mapping evidence is added.

## Unsupported project integrations

PkgLift detects root `Cartfile` or `Cartfile.resolved` metadata and confirmed Carthage paths or build phases in the Xcode project. It does not read Carthage dependency declarations, turn them into migration actions, or modify Carthage files. Confirmed Carthage presence prevents `AUTO` for the CocoaPods plan.

The static Podfile parser recognizes the exact call markers `use_react_native!`, `flutter_install_all_ios_pods`, and `capacitor_pods`. These identify React Native, Flutter, and Capacitor integration respectively and prevent `AUTO`; quoted text, comments, and longer identifier suffixes are not treated as markers. PkgLift does not claim heuristic Kotlin Multiplatform detection. Local pods and dynamically generated declarations still fail closed under the normal source and Ruby rules.

## Project and workspace selection

PkgLift discovers `.xcodeproj` and `.xcworkspace` directories recursively beneath
`--path` without descending into generated `Pods`, `.build`, `.swiftpm`,
`Carthage`, `DerivedData`, or PkgLift-owned `.pkglift` trees. Recovery copies do
not become project/workspace candidates; the separate incomplete-migration check
still refuses apply while recovery state exists. Project bundles and workspace bundles are
terminal discovery nodes, so internal Xcode metadata is not treated as another
user workspace.

All explicit selections and workspace project references are standardized and
resolved through symlinks before use. They must remain inside `--path`.
Multi-project workspaces require `--workspace` together with `--project`, and the
selected project must be an actual non-Pods reference in that workspace.
Unsupported workspace location schemes are refused instead of guessed.

## Preflight and mutation

`pkglift migrate` is a dry run. Before parsing a saved plan or project, `pkglift migrate --apply` checks the fixed recovery marker at `.pkglift/migration-in-progress`. A present marker always refuses apply, including with `--allow-dirty`. Its bounded JSON records only recovery backup and path context, never source content. This early refusal prevents a later invocation from overwriting the backup needed to recover an interrupted migration.

When no recovery marker is present, `pkglift migrate --apply` validates the entire saved AUTO contract before the first write. It regenerates the current migration evidence in memory and refuses when the saved AUTO entry no longer exactly matches the current Podfile, lockfile, registry mapping, configuration, actions, target attribution, target language profile, or supported mapping languages. It separately compares every safely comparable external `sourceProvenance` snapshot plus its version, declaration origins, and target attribution with current analysis. Added, removed, or changed evidence refuses mutation. Redacted, malformed, incomplete, conflicting, credential-bearing, or otherwise lossy provenance cannot prove equality and also refuses an unrelated `AUTO` apply. It also refuses stale project paths, missing Podfile declarations, missing or conflicting versions, and missing or ambiguous targets. Every AUTO entry must carry non-empty literal declaration provenance, explicit exact target attribution, and complete consumer-language evidence that agree with the typed actions; it must not contain external source provenance.

Older schema-1 plans remain decodable, but legacy target arrays are treated only as partial context. An AUTO entry without current provenance or consumer-language evidence is refused and must be regenerated before migration. Existing executable plans must also be regenerated with PkgLift 0.7.1 because preflight binds a plan to the version that created it.

Podfile editing uses the same parser and declaration-line evidence as analysis, including supported parenthesized calls, tab separators, and repeated declarations. Target blocks, similarly named pods, remaining CocoaPods dependencies, comments, Ruby data sections, and untouched line endings are preserved. Before committing, migration reparses the actual written Podfile and refuses completion if a migrated declaration remains or dynamic Ruby prevents verification; that failure follows normal rollback. Structural verification also uses the parser and fails closed when removal cannot be established. PkgLift does not run the Podfile as Ruby.

Registry-backed SwiftPM package references and product links are de-duplicated. Equivalent registry repository URLs with an optional `.git` suffix or trailing slash resolve to the same identity. External Git provenance uses its stricter transport boundary described above: HTTPS is not assumed equivalent to SSH. Existing requirements are preserved; a conflict stops migration.

## Git behavior

- Git repository, clean: migration may proceed.
- Git repository, dirty: `--apply` refuses by default; `--allow-dirty` is an explicit override.
- Not a Git repository: migration is allowed. Git is recommended, not mandatory.
- Unexpected `git status` failure: migration refuses because safety could not be established.

## Rollback boundary

Before applying changes, PkgLift reserves recovery state with the active migration marker, then backs up the Podfile and complete `.xcodeproj` directory under `.pkglift/backup`. The marker reservation occurs before the backup copy so that a second apply cannot race an in-progress recovery setup. During mutation, a small C signal handler records the first signal in a lock-free atomic state. It does not allocate memory, perform file I/O, or attempt rollback. The migration engine checks that state at checkpoints between writes.

For a handled `SIGINT` or `SIGTERM` before terminal commit, PkgLift attempts rollback at the next checkpoint. A successful rollback clears the active marker, finalizes the backup receipt, and exits with status `130` for `SIGINT` or `143` for `SIGTERM`. A signal observed after terminal commit reports that the files are fully migrated; it does not claim rollback occurred. A normal Swift write or edit error also attempts to restore both the Podfile and `.xcodeproj` and surfaces the original error after successful restoration. If rollback reports an error, PkgLift makes a best-effort restoration attempt for both files, preserves the marker and backup, and reports a distinct rollback failure. It does not claim that separate filesystem updates form one durable operating-system transaction.

After migration and any rollback attempt have finished, the CLI restores both previous signal dispositions and atomically closes the signal outcome. A signal recorded before successful closure is returned to Swift for the conventional exit status. A handler already dispatched on another thread but delayed until after successful closure uses async-signal-safe `_exit` with status `130` or `143`; concurrent late handlers use the first terminal signal's status. This path runs no Swift cleanup and may exit without the detailed interruption message. It is armed only after successful migration and signal-disposition restoration. An existing migration, rollback, or restoration error instead closes a failure outcome and keeps its original error reporting.

Signal ownership is deliberately one-shot within the CLI process. A later installation in the same process is refused, so a delayed handler cannot act on a reset state or a new migration. Normal CLI invocations run in separate processes; this does not prevent a later invocation from applying a valid new plan. As with any process, there is no signal-handling guarantee after it has already terminated.

On normal terminal completion, the backup carries an internal receipt that identifies it as a known completed backup and permits its later reuse. A legacy backup, or one without a valid receipt, is ambiguous and causes apply to refuse rather than replace it.

After `SIGKILL`, a crash, `SIGHUP`, or operating-system failure terminates the process, PkgLift cannot run rollback. If the recovery marker and backup survive on disk, a later apply refuses. Filesystem synchronization cannot guarantee recovery data after every power or operating-system failure. Inspect the recovery state before changing anything. If termination occurred while backups were being copied, the backup may be incomplete even though the originals have not yet been mutated; do not blindly restore a partial backup. Restore both the complete Podfile and complete `.xcodeproj` using verified recovery data or a known-good version-control/independent backup. After verifying both originals, archive the recovery marker and backup outside `.pkglift` before generating a new plan. Keep the originals and recovery data until that verification is complete; `--allow-dirty` does not bypass this refusal. PkgLift provides no automatic public recovery command.

Rollback does not extend past a successful `migrate --apply`: `pod install` and `verify` are separate, explicit steps. PkgLift does not currently offer an automatic rollback command after verification.
