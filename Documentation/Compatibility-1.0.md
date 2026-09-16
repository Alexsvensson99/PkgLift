# PkgLift 1.0 compatibility contract

G1 policy and interface inventory, based on public 0.10.0 and the
[1.0 readiness plan](Plan-1.0.md). This contract defines the intended 1.x promise;
it does not release 1.0, change the binary version, or qualify new environments.
G2–G6 remain required before that promise becomes a published support commitment.

## Versioning policy

The first 1.0.0 tag will freeze the supported public surface described here.
Within 1.x, preserve existing command names/options, documented machine-readable
meanings, public library declarations and their documented safety boundaries.
Do not remove or rename a supported surface, change an existing field's type or
meaning, add a mandatory argument, or make a previously optional input mandatory
in a minor/patch release.

New optional commands, options and APIs may be additive when existing calls
still compile and behave according to this contract. Fixes may tighten unsafe
acceptance or change a classification when new evidence demonstrates a risk.
There is no promise that a dependency remains AUTO after a safety fix, registry
update or changed project evidence. Explain such changes and required replanning
in release notes; never weaken validation for compatibility.

Deprecate a supported surface with a documented replacement and migration example
before removing it in a major version. Preserve the old source/CLI entry point
through the remaining 1.x series. Urgent safety corrections may take effect in
a patch release, but do not silently reinterpret an existing contract as permission
to mutate. Changes requiring incompatible data semantics need an explicit new
schema/profile or major version, with the old reader behavior documented.

## CLI inventory and behavior

The [root command](../Sources/PkgLiftCLI/PkgLift.swift) registers the commands below.
`-h`/`--help` is provided by ArgumentParser; root `--version` and `version` report
the PkgLift version. Human help/error prose, table layout, colors, whitespace and
progress messages are not parsing contracts.

[Common options](../Sources/PkgLiftCLI/CommonOptions.swift) are `-p`/`--path`,
`--project`, `--workspace`, `--json` and `--no-color`. They are parsed by analyze,
plan, migrate, verify, diagnostics and registry validate. This shared parsing
does not mean that every command uses every option: JSON stdout is implemented
only where listed below. `--path` defaults to the working directory.

| Command | Additional inputs and defaults | Stable effect/output boundary |
|---|---|---|
| `analyze` | `--portable-json`; `--fail-on blocked\|unresolved\|non-auto` (off by default) | No migration writes or saved plan. `--json`/`--portable-json` produce one complete analysis document; they are mutually exclusive. A matching failure policy returns 1 after output, considers direct dependencies only, and never performs migration. |
| `plan` | `--portable-json` | Always writes the full executable `.pkglift/plan.json`. `--json` emits that plan; `--portable-json` emits only a redacted review copy to stdout. Both flags together are invalid. Planning does not apply project changes. |
| `migrate` | `--apply` (false), `--allow-dirty` (false) | Default is a dry run. Apply executes only validated AUTO actions. `--allow-dirty` bypasses only the Git dirty-tree check, never recovery or evidence validation. Output is human-readable even if the shared `--json` flag is parsed. |
| `verify` | `--build` (false), `--scheme`, `--configuration`, `--destination`, `--sdk`, `--derived-data-path` | Structural checks always run. Build requires an explicit scheme; build-only settings without `--build` are refused. `--json` emits a verification document, including failed checks before its failure exit. Options are process arguments, not shell code. |
| `diagnostics` | Required `--output`; `--overwrite` (false) | Writes a minimized JSON report to the selected file; the shared `--json` flag does not select JSON stdout. Relative output is based on the working directory. A valid partial report can have success exit status; inspect its status/failures. Report writing failure is an error. |
| `registry validate` | Common options; registry discovery/configuration uses `--path` | Validates source/local/configured or bundled mappings and emits text. `--json`, `--project` and `--workspace` do not add a JSON format or a project-verification mode. |
| `podspec inspect` | Required `--podspec` and `--source-root`; `--format text\|json` (text); `--source-selection literal-only\|flat-swift-globs` (literal-only) | Explicit local observation only. It does not accept common project options, discover projects, execute CocoaPods/Ruby, generate packages or authorize migration. A complete report may describe refused evidence. |
| `version` | None | Prints the product version. It is not a schema or toolchain compatibility claim. |

Use [build verification](BuildVerification.md), [diagnostics](Diagnostics.md)
and [local inspection](LocalSourceInspection.md) for the detailed option semantics.
Never parse human error wording to decide whether a migration is safe.

### Process statuses

| Status | Actual CLI contract retained for 1.x |
|---|---|
| `0` | Command completed, help/version requested, or nothing to migrate. Check report status/classifications; this alone does not prove a build, equivalence or migration occurred. |
| `1` | Runtime/validation failure, unsafe or stale executable plan, failed verification/registry check, failed analyze policy, or unavailable local inspection. |
| `64` | ArgumentParser usage error, including missing required arguments, invalid option values and conflicting JSON flags. Some semantic input validation happens during execution and returns 1 instead. |
| `130` / `143` | Handled SIGINT/SIGTERM in the migration signal protocol. These statuses do not themselves prove rollback: terminal completion may precede the signal. Consult the [rollback boundary](MigrationSafety.md#rollback-boundary). |

SIGKILL, operating-system failures and termination of external tools have their
own platform behavior; no universal CLI status or rollback guarantee is implied.
The public `PkgLiftCore.PkgLiftExitCode` enum is a legacy numeric catalogue with
values 0…6. Its cases/raw values remain a library source contract, but the CLI
does not map errors through it. Do not expect process codes 2…6 from those names.

## JSON, YAML and profile inventory

| Surface | Current version and semantic authority |
|---|---|
| `ProjectAnalysis`, `MigrationPlan`, `VerificationResult` | Top-level `schemaVersion: 1`, ISO-8601 timestamp and `pkgLiftVersion`; see [JSON contracts](JSONSchema.md). Analysis/verification are reports. A plan is executable only after current preflight, never just because decoding succeeded. |
| `DiagnosticsReport` | Schema 1, minimized local support report with explicit status/failures. It is not an executable plan or an anonymization guarantee. |
| Portable analyze/plan stdout | `portableOutput.version: 1`; redacted review output, not a replacement executable plan. Project/dependency names may remain. |
| `.pkglift.yml` | Schema 1. `registry.additionalPaths`, `migration.allow`/`deny`, `verification.build` are model fields. The CLI still requires explicit `verify --build`; declaring a model field does not imply automatic command execution. |
| Registry YAML | Schema 1 and 2 accepted by current validation; new executable entries require schema 2 and platform evidence. Exact pod/subspec identity, product, language and version evidence still govern AUTO. See [registry contract](Registry.md). |
| `podspec inspect` report | Schema/profile v1 for literal-only, v2 for explicit flat Swift globs; selection mode is not auto-upgraded. See [local inspection](LocalSourceInspection.md). |
| Podspec semantic/assessment and generated-evidence library types | Pinned, explicitly named profiles in [Podspec semantics](PodspecSemanticModel.md) and [generated evidence](GeneratedPackageEvidence.md). These profiles remain separate from the plan schema and confer no migration authority. |

Retain existing keys, value types, enum raw values and meanings for a supported
schema. Optional new object fields can be additive. Existing supported historical
schema-1 shapes may omit counts, reason details, provenance and language/platform
fields where the documented model permits them. Missing executable evidence still
prevents AUTO execution.

**Unknown fields and unknown values differ.** Current synthesized Swift Codable
decoders ignore unknown object keys. They reject unknown values of closed enums
such as classification, integration and reason code; they do not substitute AUTO
or silently downgrade to a different known value. Generic JSON clients may retain
unknown reporting values as opaque data, but must not infer execution authority.
An unknown key is not validated or round-tripped merely because it was ignored.

Decoding also does not automatically validate `schemaVersion`: report/model
decoders can hold an unsupported integer. Callers must check the supported schema
and use operation-specific validators before interpreting or acting. Configuration
loading and registry validation perform their own schema checks. Executable-plan
checks are specified below.

Adding a case to an existing closed public Swift enum can break client switches
and older typed JSON readers. Do not label it universally compatible merely because
it adds a reporting code. Preserve supported readers and source clients, or use
an explicitly versioned API/schema and migration path; incompatible changes belong
in a major release. The existing JSON guidance to tolerate future reason codes
applies to defensive generic consumers, not a promise that old Codable enums decode them.

JSON field ordering, pretty-print whitespace, timestamps and human `message`,
`detail`, `description` or `remediation` prose are not byte-stable APIs. Where
canonical byte output is explicitly specified for inspection/evidence, retain
that profile's own canonicalization and digest rules.

## Reading a plan versus executing it

`MigrationPlan.schemaVersion` and the producer's `pkgLiftVersion` are separate.
For a plan containing executable AUTO entries, both dry run and apply require
the supported schema and **exact equality** with the running PkgLift version,
including patch versions. Thus a 1.0.0 plan must be regenerated before execution
by 1.0.1. Schema 1 remaining readable does not override this requirement.

Preflight also checks the current Podfile/lockfile, mapping, target attribution,
language/platform evidence, actions and other live evidence. A matching version
or successful JSON round trip never bypasses those checks. Use a fresh plan after
upgrading; do not edit the saved version, classification or actions to force acceptance.

Current CLI behavior returns a mutation-free no-op when no non-empty AUTO entry
exists, before executable-plan schema/version preflight. This is not acceptance
of an incompatible executable plan. Apply still checks the recovery marker first.
Unknown enum/action values may fail decoding even before the no-op decision.

Supported older report decoding is therefore distinct from forward decoding of
arbitrary future enums, and both are distinct from current execution eligibility.

## Swift library promise

[Package.swift](../Package.swift) exports six library products and the `pkglift`
executable. All documented `public` declarations of these six libraries at 1.0.0
are included in the 1.x source-compatibility promise, including initializers,
members, protocols, error types, Codable shapes and legacy typealiases. This is a
source promise on qualified toolchains, not a stable binary ABI or an ability to
reuse compiled modules across Xcode/Swift versions.

| Product | Public surface covered; representative client entry points |
|---|---|
| [PkgLiftCore](../Sources/PkgLiftCore) | Domain/report/plan models, typed reasons and identities, configuration, discovery/process helpers, diagnostics/redaction, version constants and legacy exit-code catalogue. |
| [PkgLiftCocoaPods](../Sources/PkgLiftCocoaPods) | Static Podfile/lock parsing and target mapping; caller-supplied Podspec semantic, assessment and generated-evidence APIs. `PodfileParser.parse(content:)` is a read-only entry point. No Ruby execution or automatic package generation is promised. |
| [PkgLiftXcode](../Sources/PkgLiftXcode) | Project/workspace analysis and typed editing APIs, including `WorkspaceAnalyzer.analyzeWorkspace(at:containedIn:)`. Direct availability of an editor is not permission to bypass migration preflight; product mutations remain orchestrated by Migration. |
| [PkgLiftRegistry](../Sources/PkgLiftRegistry) | `RegistryLoader` actor, exact lookup, loading/validation and typed errors. `RegistryValidator.validate(_:filePath:)` validates mappings; successful validation alone is not consumer-build equivalence. |
| [PkgLiftMigration](../Sources/PkgLiftMigration) | Classifier/planner/preflight, engine, Git safety, atomic orchestration and Core compatibility typealiases. `MigrationPlanner.generatePlan(...)` preserves unsupported dependencies as non-AUTO entries. |
| [PkgLiftVerification](../Sources/PkgLiftVerification) | Structural/build verification, explicit options and result/error types. `BuildVerificationOptions.validated()` refuses invalid process input; verification does not supply missing migration evidence. |

Internal targets `PkgLiftInspection` and `PkgLiftSignalSupport`, the CLI's internal
Swift types, test seams, private helpers and dependency internals are not exported
library promises. The `podspec inspect` CLI report is still covered separately.
Where a public signature exposes a dependency type, dependency upgrades must not
break that signature within 1.x; the dependency's entire API is not re-exported
as PkgLift's compatibility promise.

Compatible additions must preserve existing overload resolution, defaults,
Sendable/concurrency requirements and conformances for existing callers. Adding
a required protocol member, changing isolation or error-case shape can be a
source break even if the symbol name stays the same. Changes to these surfaces
need client compilation and review against the 1.0 baseline. Freeze a public API
inventory/diff baseline at G6; the current representative client tests are not an
exhaustive symbol-level compatibility proof for every future release.

## Support table and qualification state

“Baseline tested” records existing 0.10 evidence. “Pending” means no 1.0 promise
may be inferred yet. Host support, target support and detecting a language are
different dimensions. Keep pending rows visible until G2/G3 close them.

| Dimension | Candidate 1.0 boundary | Evidence/status and owner |
|---|---|---|
| Distributed host/CPU | Apple Silicon arm64, macOS 14 minimum retained | Signed 0.10 artifact and Homebrew verified. G2 [runtime smoke on macOS 14.8.9](Environments-1.0.md) passed; exact 14.0 remains untested. Minimum deployment metadata alone is insufficient. Intel distribution is outside scope. |
| Source build toolchain | Exact supported Xcode/Swift combinations, not “all later versions” | Baseline signing run [35066758613](https://github.com/Alexsvensson99/PkgLift/actions/runs/35066758613) records macOS 15.7.9 arm64 and Swift 6.1.2; workflow selects Xcode 16.4. Capture exact Xcode build and qualify supported lower/upper cells in G2. Swift tools version 6.0 in Package.swift is a syntax minimum, not proof of every Swift 6 toolchain. |
| Consumer build environment | Explicit scheme/configuration/destination/SDK; recorded CocoaPods version | Existing consumer CI selects Xcode 16.4. Complete the exact environment matrix, including CocoaPods and SDK versions, in G2. Do not infer them from the runner label. |
| Swift consumer | Mapping-dependent AUTO with complete graph evidence | Three repository-owned KeychainAccess/DeviceKit/CryptoSwift consumers have concrete Swift/iOS 15 evidence. Broader real-project and partial-migration claims are pending G3. |
| Objective-C / Swift+Objective-C | Only mappings supporting every detected language | Repository-owned SDWebImage mixed-language fixture is baseline evidence. Every additional advertised project shape needs G3 evidence. |
| Objective-C++, C, C++ | Detection; non-automatic without exact complete language evidence | No new mapping or positive support is introduced. Preserve conservative refusal. |
| Target platform/deployment | Mapping-specific, not inherited from host OS support | Schema-2 consumer mappings restrict Swift/iOS 15+. Other mapping claims need their own evidence; macOS/iOS detection is not a universal migration promise. G2/G3 record the accepted matrix. |
| Project/workspace/targets | Explicit selection when ambiguous, containment and exact target attribution | Existing selection/refusal tests and read-only pilots. Full real-project workspace/multi-target and retained-CocoaPods builds remain G3 qualification. |
| Existing SwiftPM + remaining CocoaPods | Supported only with nonconflicting, validated partial state | Preflight and preservation behavior exist; repeatable full mixed-manager build evidence is pending G3. |
| External Git/local pods, unsupported Ruby, Carthage/RN/Flutter/Capacitor | Preserve current non-automatic boundaries | See [migration safety](MigrationSafety.md). No new source resolver, dynamic execution or manager conversion is promised. KMP heuristic detection is not claimed. |
| Recovery | Existing handled-signal rollback and fail-closed markers; manual recovery outside automatic boundary | Full user-flow drills remain G4. Neither 1.x compatibility nor exit status implies power-loss recovery. |

The local toolchain used to validate G1 is a development observation, not a newly
qualified support cell. G1 does not silently widen the macOS/Xcode or consumer matrix.

## Executable examples and evidence map

The test [PublicAPIContractTests](../Tests/PkgLiftPublicContractTests/PublicAPIContractTests.swift)
imports all six libraries without `@testable`. Its read-only examples combine
Podfile parsing, bundled lookup/validation and conservative planning for an
unmapped dependency, then exercise typed workspace-containment and build-option
refusal. It is a public-access/client smoke test, not a real-project migration or ABI test.

| Contract boundary | Focused evidence |
|---|---|
| Older optional report fields and current round trips | [ProjectAnalysisTests](../Tests/PkgLiftCoreTests/ProjectAnalysisTests.swift); [MigrationPlanPreflightTests](../Tests/PkgLiftMigrationTests/MigrationPlanPreflightTests.swift) |
| Unknown object fields versus unknown enums | [JSONContractCompatibilityTests](../Tests/PkgLiftCoreTests/JSONContractCompatibilityTests.swift) |
| Executable AUTO schema/version rejection before writes | [CommandContextMigrationTests](../Tests/PkgLiftCLITests/CommandContextMigrationTests.swift); compare Podfile/project/plan bytes and absence of transaction state |
| Stale declarations/targets and missing language evidence | Existing cases in the same CLI tests and preflight tests; no weakening of refusal |
| Usage/general statuses and JSON flag rules | [CLIExitContractTests](../Tests/PkgLiftCLITests/CLIExitContractTests.swift), [PortableJSONOptionTests](../Tests/PkgLiftCLITests/PortableJSONOptionTests.swift), [AnalyzeFailurePolicyTests](../Tests/PkgLiftCLITests/AnalyzeFailurePolicyTests.swift) |
| Signal statuses and recovery boundaries | [MigrateInterruptionTests](../Tests/PkgLiftCLITests/MigrateInterruptionTests.swift) and [atomic tests](../Tests/PkgLiftMigrationTests/AtomicMigrationTests.swift) |
| Configuration, registry and inspection schema/profile rules | [ConfigurationTests](../Tests/PkgLiftCoreTests/ConfigurationTests.swift), [registry tests](../Tests/PkgLiftRegistryTests), [inspection tests](../Tests/PkgLiftInspectionTests), [Podspec tests](../Tests/PkgLiftCocoaPodsTests) |

All G1 evidence is local until reviewed/integrated through normal protected CI.
G2 environment qualification, G3 project breadth, G4 recovery drills, G5 safety
review and G6 exact release acceptance remain separate, open gates.

### Local G1 validation

Verified on 2026-09-16 with arm64 macOS 27.0 (26A428), Xcode 27.0 (27A266a)
and Apple Swift 6.4 (`swiftlang-6.4.0.34.1`). The final commands were:

```sh
swift test --build-system native --jobs 4 --disable-automatic-resolution
swift build --build-system native --jobs 4 --disable-automatic-resolution
swift run --build-system native --skip-build pkglift registry validate
```

All 576 tests passed: 352 XCTest cases and 224 Swift Testing cases, including
the six new G1 cases. The explicit build passed; all 25 mappings validated.
The six focused cases also passed separately. Local Markdown links, anchors and
whitespace were checked, and an independent source review found no contract
discrepancies. No runtime behavior, mapping, binary version or safety rule changed.

The default Swift Build engine failed while signing a generated test bundle
with `com.apple.FinderInfo` metadata in this checkout. The native engine then
hit a generated-runner modification during its initial build; an incremental
retry completed, followed by the passing final runs above. Native is deprecated
in this toolchain. These results establish G1 local contract coverage only;
they do not qualify the default engine or this environment for the G2 support
matrix. Resolve/reproduce that build-environment limitation during G2 before
advertising such support. Protected CI has not run for this local change.

The subsequent [G2 environment investigation](Environments-1.0.md) isolates the
sync-folder signing failure and fixes modern registry-bundle resource lookup.
It records successful local verification of both build engines without widening
the published support promise.
