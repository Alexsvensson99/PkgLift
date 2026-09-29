# Targeted migration-safety review for 1.0

Status: **targeted source and test-evidence review completed on 2026-09-29;
exact-candidate validation and the remaining G5 evidence work are pending.** The
reviewed source baseline is `c5c32ee8e3598975a97dc53207b29596724f65f1`.

This is an independent, bounded review of the migration-integrity paths named by
G5. It is not a repository-wide security audit, a dependency vulnerability scan,
a mapping-by-mapping upstream support audit or release-candidate acceptance. No
build or test command was run for this review; the dispositions below come from
current source and existing focused tests. The exact 1.0 candidate still needs
the tests and protected acceptance already required by G6. This documentation
review does not add a separate rerun of completed G4 local recovery scenarios.

## Result and finding disposition

No critical or high-severity migration-integrity defect was confirmed in the
reviewed CLI path. The CLI regenerates current evidence, preflights the saved
plan and enters mutation only with the resulting prepared operations. One low
public-API precondition gap was recorded. It does not give an untrusted project
new authority and does not bypass the CLI; its 1.0 documentation disposition is
now addressed in the compatibility contract.

| ID | Severity | Status | Affected boundary | Disposition |
|---|---|---|---|---|
| G5-SR-01 | Low | Addressed for the 1.0 documentation contract; optional ergonomics follow-up | Direct `PkgLiftMigration` library use; CLI unaffected | [Compatibility-1.0.md](Compatibility-1.0.md#migration-library-caller-responsibility) now states the caller responsibility and shows the required saved/current plan plus current-target preflight before engine execution. Source comments, type-level hardening or a non-`@testable` executable client case may improve later ergonomics; they are not required by this finding for 1.0. No new test execution is claimed. |

### G5-SR-01 — the public execution precondition is easy to miss

`PreparedMigration` is described as fully validated, but its public
initializer accepts any removal/add/link combination
([MigrationPlanPreflight.swift lines 4–42](../Sources/PkgLiftMigration/MigrationPlanPreflight.swift#L4-L42)).
`MigrationEngine.execute(prepared:...)` says it executes operations that have
already passed preflight, then verifies that requested Podfile declarations were
found, performs the supplied operations and checks only the written Podfile
before committing recovery state
([MigrationEngine.swift lines 23–24](../Sources/PkgLiftMigration/MigrationEngine.swift#L23-L24),
[46–113](../Sources/PkgLiftMigration/MigrationEngine.swift#L46-L113)). A library
caller can therefore accidentally construct an incomplete operation set, such as
a removal with no corresponding package addition or product link, and still meet
the engine's local postconditions.

This is not classified as a security vulnerability or a broken CLI guarantee.
The caller is in the same trusted process and already has direct mutation APIs;
the architecture documents preflight before execution
([Architecture.md lines 24–34](Architecture.md#L24-L34)), and the compatibility
contract says that direct editor availability is not permission to bypass
migration preflight
([Compatibility-1.0.md lines 138–154](Compatibility-1.0.md#L138-L154)). The CLI
does call the regenerated-plan preflight before apply
([MigrateCommand.swift lines 43–58](../Sources/PkgLiftCLI/MigrateCommand.swift#L43-L58)).

The public client evidence exercises parsing, planning and refusal but does not
demonstrate this mandatory library sequence
([PublicAPIContractTests.swift lines 10–68](../Tests/PkgLiftPublicContractTests/PublicAPIContractTests.swift#L10-L68)).
The [compatibility contract](Compatibility-1.0.md#migration-library-caller-responsibility)
now supplies the concrete `saved plan + current plan + current TargetInfo ->
preflight -> engine` example and lists the caller's other duties. That addresses
this Low finding for the 1.0 documentation contract without changing source or
claiming a new test run. Source comments, additional public-client coverage or a
type-level hardening proposal may be considered after 1.0 as usability work.

## Caller responsibility for public library APIs

A direct `PkgLiftMigration` caller is responsible for preserving the same
sequence as the CLI: build a current plan from the current project, call the
`MigrationPlanPreflight.prepare(plan:currentPlan:availableTargetInfos:)`
overload, and pass only that call's returned `PreparedMigration` to the engine.
The caller must not construct a substitute value, omit current-plan comparison
or turn `REVIEW`, `BLOCKED` or `UNKNOWN` entries into operations. Direct
`PkgLiftXcode` editor calls are lower-level mutations against caller-selected
paths; their availability is not evidence that target, package or product
selection passed migration preflight. The CLI owns and enforces this sequence
for command-line use. The compatibility contract now makes this existing
responsibility explicit. This does not expand the engine's trust boundary or
require a new design in this review.

## Reviewed trust boundary

The reviewed inputs are a potentially complex or adversarial Podfile,
Podfile.lock, Xcode project/workspace, registry/configuration and saved plan
inside a project selected by the operator. The protected assets are the exact
Podfile and project bytes, dependency and version identity, destination target,
retained CocoaPods state, and recovery evidence. The safety objective is to
refuse ambiguity before a write, keep paths within the selected project, mutate
only exact validated actions and restore both mutation inputs when the apply
sequence fails.

Another process running as the same user can rename or replace project paths.
That actor already has the authority to edit the project directly. The review
therefore treats concurrent-writer and universal power-loss behavior as explicit
filesystem limitations, not as a new privilege boundary. The same assumption is
recorded by the plan writer and recovery contract.

## Control review

### Static parsing and source identity — no defect confirmed

- `PodfileParser` never evaluates Ruby, marks unsupported lexical or nesting
  structure dynamic, and treats unknown executable statements as non-static
  evidence
  ([PodfileParser.swift lines 7–18](../Sources/PkgLiftCocoaPods/PodfileParser.swift#L7-L18),
  [40–50](../Sources/PkgLiftCocoaPods/PodfileParser.swift#L40-L50),
  [99–141](../Sources/PkgLiftCocoaPods/PodfileParser.swift#L99-L141),
  [712–770](../Sources/PkgLiftCocoaPods/PodfileParser.swift#L712-L770)). Literal
  declarations retain their physical line, source and target attribution; an
  unclosed scope makes the file dynamic
  ([lines 189–243](../Sources/PkgLiftCocoaPods/PodfileParser.swift#L189-L243)).
- `PodfileLockParser` validates YAML node shape before dictionary decoding so
  duplicate source/ref keys cannot become last-value-wins evidence. Malformed
  source sections, unsupported spec repositories and conflicting repository
  assignments remain bounded evidence or typed refusal
  ([PodfileLockParser.swift lines 29–60](../Sources/PkgLiftCocoaPods/PodfileLockParser.swift#L29-L60),
  [194–245](../Sources/PkgLiftCocoaPods/PodfileLockParser.swift#L194-L245),
  [400–457](../Sources/PkgLiftCocoaPods/PodfileLockParser.swift#L400-L457)).
- Exact pod/subspec names are used when declaration and lockfile evidence are
  joined. Missing declarations keep unresolved legacy attribution, and aggregation
  retains partial/unresolved counts rather than copying a target from another
  declaration
  ([PodfileTargetMapper.swift lines 11–31](../Sources/PkgLiftCocoaPods/PodfileTargetMapper.swift#L11-L31),
  [74–143](../Sources/PkgLiftCocoaPods/PodfileTargetMapper.swift#L74-L143),
  [146–220](../Sources/PkgLiftCocoaPods/PodfileTargetMapper.swift#L146-L220)).

Existing focused evidence includes fail-closed Ruby, control-character, Unicode,
nesting, helper and scope cases in
[PodfileParserTests.swift](../Tests/PkgLiftCocoaPodsTests/PodfileParserTests.swift),
lockfile source/conflict cases in
[PodfileLockParserTests.swift lines 70–528](../Tests/PkgLiftCocoaPodsTests/PodfileLockParserTests.swift#L70-L528),
and exact/partial target aggregation in
[PodfileTargetMapperTests.swift lines 70–237](../Tests/PkgLiftCocoaPodsTests/PodfileTargetMapperTests.swift#L70-L237).

### AUTO, target, language and platform gates — no defect confirmed

`MigrationClassifier` accumulates independent reasons for missing or mismatched
registry identity, transitive or unrepresentable declarations, unsupported
source evidence, project-level CocoaPods behavior and unverified mappings
([MigrationClassifier.swift lines 153–318](../Sources/PkgLiftMigration/MigrationClassifier.swift#L153-L318)).
AUTO also requires a complete non-empty target language profile, reviewed header
imports, support for every detected language, a valid platform schema and a
compatible concrete target environment
([lines 320–443](../Sources/PkgLiftMigration/MigrationClassifier.swift#L320-L443)).
Multiple, partial or unresolved targets and unstable/unrepresentable versions
remain non-automatic; AUTO is returned only when the complete reason set is empty
([lines 445–554](../Sources/PkgLiftMigration/MigrationClassifier.swift#L445-L554)).

`CommandContext` independently requires one exact attribution and one matching
Xcode target, applies deny/allow policy conservatively, and demotes an otherwise
AUTO result when package, declaration, target, language or platform evidence is
incomplete
([CommandContext.swift lines 84–122](../Sources/PkgLiftCLI/CommandContext.swift#L84-L122),
[127–147](../Sources/PkgLiftCLI/CommandContext.swift#L127-L147),
[174–209](../Sources/PkgLiftCLI/CommandContext.swift#L174-L209)). Focused tests
cover external sources, target ambiguity, language/header evidence and platform
requirements in
[MigrationClassifierTests.swift](../Tests/PkgLiftMigrationTests/MigrationClassifierTests.swift)
and incomplete/ambiguous Xcode evidence in
[XcodeProjectAnalyzerTests.swift](../Tests/PkgLiftXcodeTests/XcodeProjectAnalyzerTests.swift).

### Saved-plan freshness — no defect confirmed

The executable preflight validates both schemas, compares the complete current
external and registry-source snapshots, validates the saved operations and then
requires every saved AUTO entry to equal the regenerated current entry
([MigrationPlanPreflight.swift lines 104–133](../Sources/PkgLiftMigration/MigrationPlanPreflight.swift#L104-L133),
[446–565](../Sources/PkgLiftMigration/MigrationPlanPreflight.swift#L446-L565)).
It also binds execution to the exact PkgLift version and reconstructs the only
accepted remove/add/link action sequence from non-empty package, version,
declaration, exact-target, language, header and platform evidence
([lines 175–320](../Sources/PkgLiftMigration/MigrationPlanPreflight.swift#L175-L320),
[323–409](../Sources/PkgLiftMigration/MigrationPlanPreflight.swift#L323-L409)).
The overload without a regenerated current plan refuses source snapshots it
cannot compare safely
([lines 152–173](../Sources/PkgLiftMigration/MigrationPlanPreflight.swift#L152-L173)).

The existing tests cover stale external and registry evidence, retained entries,
lossy provenance, plan-version mismatch, target ambiguity, language/profile
changes and platform changes in
[MigrationPlanPreflightTests.swift lines 31–838](../Tests/PkgLiftMigrationTests/MigrationPlanPreflightTests.swift#L31-L838).

### Path containment and plan publication — no defect confirmed

Workspace analysis standardizes and resolves the workspace, root and every
project reference, applies component-aware containment and rejects unsupported
location schemes
([WorkspaceAnalyzer.swift lines 52–88](../Sources/PkgLiftXcode/WorkspaceAnalyzer.swift#L52-L88),
[174–213](../Sources/PkgLiftXcode/WorkspaceAnalyzer.swift#L174-L213)). Existing
tests reject absolute, relative-absolute and symlink escapes
([WorkspaceAnalyzerTests.swift lines 76–159](../Tests/PkgLiftXcodeTests/WorkspaceAnalyzerTests.swift#L76-L159)).

The current `PlanFileWriter` fix resolves the selected root once, walks retained
no-follow directory descriptors, refuses non-directory/symlink bindings, stages a
mode-0600 exclusive file, synchronizes it and revalidates the destination,
ancestor bindings and staged inode before same-directory publication
([PlanFileWriter.swift lines 4–74](../Sources/PkgLiftCLI/PlanFileWriter.swift#L4-L74),
[81–127](../Sources/PkgLiftCLI/PlanFileWriter.swift#L81-L127),
[136–208](../Sources/PkgLiftCLI/PlanFileWriter.swift#L136-L208)). The focused
tests cover parent links, special destinations, hard links, ancestor rebinding,
destination replacement and temporary-file substitution
([PlanWriteTests.swift lines 7–202](../Tests/PkgLiftCLITests/PlanWriteTests.swift#L7-L202)).
This review found no regression in that fix.

### Partial-state preservation — no defect confirmed

Podfile editing removes only exact declaration lines returned by the static
parser and preserves every untouched physical line, including CRLF and final
newline state
([PodfileEditor.swift lines 28–52](../Sources/PkgLiftMigration/PodfileEditor.swift#L28-L52)).
The engine refuses before mutation if any requested declaration is absent and
reparses the written file before commit
([MigrationEngine.swift lines 56–67](../Sources/PkgLiftMigration/MigrationEngine.swift#L56-L67),
[105–112](../Sources/PkgLiftMigration/MigrationEngine.swift#L105-L112)). The
Xcode editor refuses conflicting package requirements and writes only the PBX
graph rather than reserializing schemes, workspaces or breakpoints
([XcodeProjectEditor.swift lines 51–102](../Sources/PkgLiftXcode/XcodeProjectEditor.swift#L51-L102),
[201–213](../Sources/PkgLiftXcode/XcodeProjectEditor.swift#L201-L213)).

Preservation tests cover comments/data/line endings, similarly named pods and
missing declarations
([PodfileEditorTests.swift lines 10–97](../Tests/PkgLiftMigrationTests/PodfileEditorTests.swift#L10-L97)),
as well as sibling targets, schemes, breakpoints, existing project references
and requirement conflicts in
[XcodeProjectEditorTests.swift](../Tests/PkgLiftXcodeTests/XcodeProjectEditorTests.swift).

### Atomic write and rollback sequence — no defect confirmed

Apply checks incomplete recovery before reading the plan or a possibly partial
project, regenerates and preflights current evidence, then checks Git state and
the selected project path before entering the engine
([MigrateCommand.swift lines 35–58](../Sources/PkgLiftCLI/MigrateCommand.swift#L35-L58),
[73–108](../Sources/PkgLiftCLI/MigrateCommand.swift#L73-L108)). The engine places
the Podfile and complete selected `.xcodeproj` inside one `AtomicMigration`
sequence
([MigrationEngine.swift lines 69–113](../Sources/PkgLiftMigration/MigrationEngine.swift#L69-L113)).

`AtomicMigration` reserves an exclusive no-follow marker, validates non-symlink
originals and recovery-path separation, completes and synchronizes the backup
before mutation, synchronizes the originals before commit and restores all
backed-up inputs after an action failure
([AtomicMigration.swift lines 74–209](../Sources/PkgLiftMigration/AtomicMigration.swift#L74-L209),
[254–303](../Sources/PkgLiftMigration/AtomicMigration.swift#L254-L303)). Receipt
publication is synchronized before the owned marker is removed; rollback stages
each restored input and reports every failure while retaining incomplete recovery
state
([lines 305–345](../Sources/PkgLiftMigration/AtomicMigration.swift#L305-L345),
[406–506](../Sources/PkgLiftMigration/AtomicMigration.swift#L406-L506)). Existing
tests cover action failure, ambiguous backup, cancellation during backup,
concurrent apply, rollback failure, missing originals and marker symlinks
([AtomicMigrationTests.swift lines 6–210](../Tests/PkgLiftMigrationTests/AtomicMigrationTests.swift#L6-L210));
real signal checkpoints and the SIGKILL marker/refusal path are covered by
[MigrateInterruptionTests.swift lines 22–168](../Tests/PkgLiftCLITests/MigrateInterruptionTests.swift#L22-L168).

## Explicit limitations and pending validation

- Plan publication and migration rollback do not claim a universal filesystem
  transaction against another same-authority process or every power-loss point.
  The descriptor binding checks, marker and synchronized backup reduce exposure;
  they do not create that guarantee.
- Automatic rollback ends when `migrate --apply` commits. A later `pod install`,
  package resolution or build can modify files outside the internal Podfile and
  `.xcodeproj` backup. The independent full-workflow baseline and manual recovery
  procedure remain required by [Recovery-1.0.md](Recovery-1.0.md).
- Registry validation proves schema and bounded mapping fields. It does not
  authenticate an upstream repository or prove every package version, product,
  consumer language or platform. G5 still needs the separate mapping-specific
  support-claim audit required by the 1.0 plan.
- This review did not exercise malformed filesystem races, fault injection,
  parser fuzzing, dependency scanning, CodeQL, installation, signing,
  notarization, package resolution or a real consumer build.
- Focused tests cited above were inspected as regression evidence but were not
  rerun. The exact frozen 1.0 source and built artifact must pass the required
  focused tests, complete suite, protected CI and installed-style candidate
  scenarios already assigned by the release plan. A documentation-only update or
  this Low disposition does not itself require rerunning the eleven completed
  local G4 recovery cases. Until the remaining receipts exist, this document
  records a review disposition only and does not close G5 or G6.
