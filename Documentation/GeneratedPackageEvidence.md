# Generated-Package Evidence Contract

Status: **v0.6 Stage 1 merged and publicly released as v0.6.0 on 2026-09-05.**
Final released-artifact and distribution evidence is recorded in the
[v0.6 release evidence](GeneratedPackageV06ReleaseEvidence.md).

This document defines the evidence boundary between the released v0.5
declaration assessment and the synthetic, read-only S1 blueprint. The recovered
Stage 0 design was restored in commit `12b8a6b`. Stage 1 implements Option A,
approved on 2026-09-04 and merged in [PR #84](https://github.com/Alexsvensson99/PkgLift/pull/84).
It does not establish a manifest shape or authorize
package generation, publication, or migration.

## Purpose

PkgLift v0.5 answers a deliberately narrow question: whether the declarations
already represented by one caller-supplied Podspec JSON document require a
downgrade under pinned CocoaPods and SwiftPM profiles. It does not establish
which files CocoaPods selected, whether a package target is complete, or
whether a generated package would preserve build or runtime behavior.

v0.6 must keep those claims separate. A future blueprint may describe only
facts supplied under an explicit evidence contract. It must never turn
`declarationCompatible` into a package-validity certificate or reinterpret a
v0.5 reason as if the missing evidence had already been supplied.

## Hard boundary

Stage 1 is a pure value transformation inside `PkgLiftCocoaPods`. It accepts
caller-owned JSON bytes and explicit evidence, and hashes those in-memory
values. It does not:

- read a Podspec file or declared source paths from disk;
- expand globs, traverse directories, follow symlinks, or hash local files;
- execute Ruby or CocoaPods, start another process, or access the network;
- resolve package identities, versions, dependencies, or products;
- generate, render, validate, or write `Package.swift`;
- inspect or modify an Xcode project, workspace, Podfile, or lockfile;
- change the CLI, registry, classifier, planner, preflight, migration,
  verification, or Xcode modules; or
- change migration-plan schemas, `AUTO` eligibility, or `migrate --apply`.

All later stages remain read-only until a separately reviewed generation
milestone explicitly replaces this boundary.

## Why the four v0.5 outcomes are insufficient

| v0.5 outcome | What it establishes | Evidence still missing for a blueprint |
| --- | --- | --- |
| `declarationCompatible` | No already-modeled declaration produced a downgrade under the pinned profiles. | Effective file selection, file existence/content, languages, package topology, dependency products, package identity, source provenance, and build/runtime equivalence. |
| `requiresGeneratedMetadata` | At least one known declaration category would need explicit future package metadata. | The metadata itself, its binding to the declaration, and proof that it is complete and noncontradictory. |
| `indeterminate` | Some evidence is unknown, deferred, opaque, incomplete, inherited, or requires inspection. | A deterministic resolution of every indeterminate reason. S1 defines no positive path for this outcome. |
| `unsupported` | At least one explicit declaration is outside the pinned safe profile. | A reviewed compatibility model. S1 defines no workaround or positive path for this outcome. |

The result must carry the original v0.5 schema and profile identifiers
unchanged. It must retain the original outcome and reasons rather than emit a
second, more optimistic name for the same assessment.

## Required additional evidence

Every evidence value is caller-supplied. The assessor validates shape,
internal consistency, canonical ordering, and digest bindings as a pure value
transformation. It derives the inspection and v0.5 assessment from the exact
JSON bytes supplied to this call. It recomputes the Podspec digest, snapshot
identifier digest, and canonical inventory digest. Source-file content digests,
language, regular-file status, completeness and consumer context remain caller
assertions: no filesystem or source contents are inspected.

### Snapshot identity and provenance

The evidence must bind all inputs to one immutable candidate snapshot:

- exact Podspec name and version matching the inspected root node;
- SHA-256 of the exact caller-owned Podspec JSON bytes;
- an opaque caller-owned source-snapshot identifier, SHA-256 of that identifier's
  UTF-8 bytes, and SHA-256 for the inventory evidence;
- an explicit reviewed evidence-provider profile identifier and schema version;
- the same CocoaPods and SwiftPM profile identifiers as the v0.5 assessment;
- an exact binding to the assessment schema, outcome, and canonical reasons;
  and
- explicit completeness claims for every inventory, including empty ones.

These values are **caller-supplied snapshot provenance**, not verified source
provenance. A later evidence provider must define how it obtains and verifies
the bytes before PkgLift may make a stronger claim.

Every SHA-256 is exactly 64 lowercase hexadecimal characters, with no prefix,
separator, uppercase form, or alternate encoding. A provider identifier must
match `^[a-z0-9][a-z0-9.-]{0,63}/v[1-9][0-9]*$` and be present in a reviewed
provider-profile registry; arbitrary caller-defined providers are invalid. A
snapshot identifier must match `^[a-z0-9][a-z0-9._-]{0,127}$`.

Those grammars establish canonical encoding, not privacy. The reviewed provider
is responsible for rejecting paths, URLs, account or repository names, refs,
credentials, and other sensitive labels. The raw snapshot identifier is
input-only; a future assessment artifact may carry only its SHA-256 digest.

### Files and selection

The evidence must distinguish the raw Podspec declaration from its claimed
effective file selection. The first candidate accepts literal file paths only;
glob semantics remain outside the contract:

- each raw root `source_files` entry is one canonical, repository-relative
  literal file path with no glob metacharacters;
- each entry is referenced by its stable semantic-model index, without copying
  private path text into the result;
- each entry maps one-to-one to the same path in the selected-file inventory;
- the union is a non-empty, unique, lexicographically sorted inventory;
- every path is UTF-8, repository-relative, slash-separated, and canonical;
- absolute paths, empty segments, `.` or `..` segments, globs, backslashes,
  control characters, and duplicate or case-colliding paths are invalid;
- every file has a caller-supplied SHA-256 content digest and exactly one
  language classification; and
- every selected file belongs to exactly one package target.

An inventory cannot silently include files that no declaration selected or
omit files while still claiming completeness. Path-extension inference alone
is not language evidence.

### Languages and consumer context

The first candidate shape is Swift-only. The evidence must state:

- that every selected source is Swift;
- that the language inventory is complete;
- exactly one intended Apple consumer platform and a canonical caller-supplied
  minimum deployment version; and
- the caller-supplied consumer-language profile used for the comparison.

This does not prove compilation, deployment-target compatibility, ABI
compatibility, or runtime behavior. Objective-C, Objective-C++, C, C++, mixed
language, generated-source, macro, plugin, and executable target shapes remain
ineligible.

### Target and product topology

The evidence must describe exactly:

- one regular package target;
- one library product containing only that target;
- one source-root relationship covering the complete selected-file inventory;
- no test, executable, macro, plugin, binary, system-library, or auxiliary
  target; and
- no normalized, guessed, or collision-resolved names.

The package, product, and target identity must equal the Podspec root name
byte-for-byte and must already satisfy the future pinned SwiftPM identifier
rules. An invalid name is an ineligible shape, not permission to invent one.

### Dependencies, resources, and build semantics

The first candidate shape requires explicit, complete empty inventories for:

- CocoaPods dependencies and translated SwiftPM dependency products;
- resources and resource bundles;
- public/private/project headers;
- frameworks, weak frameworks, and libraries;
- vendored artifacts;
- module maps and custom module/header layouts;
- compiler flags and xcconfig-style settings;
- configuration-specific dependencies;
- ARC controls, excluded files, and preserved paths; and
- generated files, scripts, hooks, and other deferred declarations.

Absence must be evidence, not omission or a default inserted during decoding.

## Stage 0 finding: the original positive gate could not describe useful sources

The original roadmap said that `declarationCompatible` was necessary for a
positive blueprint. The released v0.5 profile also assigns
`sourceSelectionRequiresGeneratedMetadata` whenever root `source_files` is
present. Its only `declarationCompatible` fixture is a metadata-empty Podspec
containing name and version alone.

Those facts leave no useful source-bearing positive case:

1. An explicit `source_files` declaration makes the v0.5 outcome
   `requiresGeneratedMetadata`, so it fails the literal roadmap gate.
2. A metadata-empty Podspec can be `declarationCompatible`, but a later
   non-empty caller inventory has no modeled declaration to bind to.
3. Treating that unbound inventory as the CocoaPods selection would be a new
   inference and could describe files the pod never selected.
4. An empty source inventory avoids the contradiction but does not provide the
   intended Swift library blueprint.

Stage 0 therefore proposed the evidence-specific rule below. Stage 1 implements
that rule while preserving the released v0.5 outcome and reasons byte-for-byte
in canonical encoding.

## Reviewed eligibility decision

### Option A — discharge one explicit metadata reason (approved)

Preserve the v0.5 outcome and reasons exactly, but allow the v0.6
assessment to consider one reason discharged only when the corresponding
caller-supplied evidence is complete and consistent.

The initial candidate shape, `S1`, requires:

- one root library node with no subspecs or raw platform scopes;
- implicit-all default-subspec policy and no unsupported/deferred fields;
- a non-empty root `source_files` declaration made only of unique canonical
  literal Swift file paths, and no other declaration category;
- no Podspec `source` field: v0.5 retains that field as deferred evidence, so a
  conventional source-declaring Podspec is outside `S1`;
- a v0.5 assessment whose outcome remains `requiresGeneratedMetadata` and
  whose complete reason set is exactly
  `sourceSelectionRequiresGeneratedMetadata` at `/source_files`;
- all snapshot, selection, file, Swift-language, consumer, topology, empty
  inventory, and provenance evidence defined above; and
- no claim beyond eligibility to construct one read-only structural blueprint.

The roadmap now records this narrow discharge rule. A metadata-empty
`declarationCompatible` result does not qualify for S1; the full singleton
source-selection reason set and all separate evidence are required.

`S1` is therefore a repository-owned, synthetic local evidence slice. It can
exercise the structural contract but cannot claim support for a conventional
published Podspec, which normally carries source provenance. Supporting that
shape requires separately typed provenance semantics; the generic
`deferredCocoaPodsSemantic` reason is never dischargeable by this profile.

### Alternatives considered in Stage 0

Retaining the literal `declarationCompatible` gate would have left no useful
source-bearing positive blueprint. Weakening or renaming v0.5 would have
invalidated the released contract. Option A was approved for local Stage 1
implementation on 2026-09-04; the restored Stage 0 commit retains the full
decision comparison.

## Read-only result states

The public result is `GeneratedPackageBlueprintAssessment`. Its four outcomes
correspond to the first four rows; invalid contracts throw
`GeneratedPackageEvidenceError` with no caller-controlled values in the error.

| State | Meaning |
| --- | --- |
| Blueprint candidate | The reviewed eligibility option is satisfied and every required evidence field for `S1` is canonical, complete, and internally consistent. This is not package validity or permission to generate. |
| Insufficient evidence | Required caller evidence is missing, incomplete, unbound, or lacks a completeness/provenance claim. |
| Contradictory evidence | Two supplied values disagree, such as identity, profile, digest binding, selection membership, language, target, or product references. |
| Ineligible shape | The Podspec or caller evidence contains a known shape outside `S1`, including subspecs, platform scopes, another declaration category, multiple targets/products, resources, dependencies, or non-Swift sources. |
| Invalid contract | Schema/profile, path, digest, canonical ordering, uniqueness, or decoding invariants are invalid. The assessor returns a typed error without a candidate. |

All observed reasons must be retained, deduplicated, and sorted
deterministically. Adding evidence may resolve a specifically modeled missing
field, but it must never erase a contradiction or make an ineligible shape
more permissive.

Precedence is contradictory evidence, then ineligible shape, then insufficient
evidence. All observed reasons remain in the result regardless of precedence.
A complete-but-empty inventory contradicting a nonempty declaration therefore
retains both the missing-sources reason and the cardinality mismatch. Only an
empty unresolved reason list can produce a blueprint candidate.

## Mandatory negative cases

| Case | Required result |
| --- | --- |
| v0.5 assessment without caller evidence | Insufficient evidence |
| Empty, duplicate, unsorted, case-colliding, or unbound source inventory | Invalid, insufficient, or contradictory evidence; never a candidate |
| Raw or inventoried absolute path, glob, backslash, control character, empty segment, `.` or `..` | Invalid contract |
| Missing or malformed SHA-256, provider/snapshot identifier, unregistered provider profile, provider schema, or snapshot binding | Invalid or insufficient evidence |
| Podspec identity/version/profile that does not match inspection and assessment | Contradictory evidence |
| Product referencing an unknown target, file with no target, or more than one target/product | Contradictory or ineligible shape |
| Non-Swift, mixed, generated, executable, plugin, macro, binary, or system-library input | Ineligible shape |
| Any dependency product, resource, header, linker input, artifact, module map, flag, build setting, ARC control, exclusion, or preserved path | Ineligible shape |
| Any subspec, explicit default selection, platform scope, unknown/deferred field, or unsupported declaration | Ineligible shape |
| Podspec `source` field or any `deferredCocoaPodsSemantic` reason | Ineligible shape; no generic deferred reason is dischargeable |
| Any v0.5 `indeterminate` or `unsupported` outcome | Ineligible shape |
| `requiresGeneratedMetadata` with more than the reviewed dischargeable reason set | Ineligible shape |
| Unknown schema/profile, duplicate/noncanonical reasons, or malformed public v0.5 model | Typed invalid-contract error or fail-closed result |
| Repeated assessment and encoding of identical values | Byte-identical canonical output |

## Determinism and privacy requirements

Stage 1 must:

- use an explicit schema version and pinned CocoaPods, SwiftPM, evidence-provider,
  and path-normalization profiles;
- reject unknown profiles rather than falling forward to current behavior;
- require the canonical lowercase SHA-256 and opaque identifier grammars above;
- accept provider identifiers only from the reviewed profile registry and never
  encode a raw snapshot identifier in the assessment result;
- use immutable `Sendable` and `Equatable` values, a private `Decodable` input,
  and a separately validated `Codable` portable result;
- reject missing fields instead of supplying permissive defaults;
- sort set-like evidence canonically while preserving explicitly ordered input
  only where order is semantic;
- reject duplicates and contradictions rather than choosing a winner;
- produce byte-stable canonical encoding for identical values; and
- keep raw patterns, local absolute paths, source URLs, credentials, flags,
  build-setting values, dependency names, and other caller secrets out of the
  assessment artifact.

Digests and stable indices may identify caller-owned evidence without copying
it into a portable result. Privacy bounding must never be described as proof
that the omitted data was safe or correct.

## Pinned Stage 1 API and encoding

`GeneratedPackageBlueprintAssessor.assess(podspecJSON:evidence:)` takes exact
in-memory JSON `Data` and optional `GeneratedPackageEvidence`. It never accepts
a separately manufactured inspection. The evidence's v0.5 assessment is a
binding that must equal the freshly computed assessment in its entirety.

The private input and `GeneratedPackageSnapshot` deliberately do not conform
to `Encodable`. `GeneratedPackageInventory` is Codable solely so providers can
construct its canonical digest. Its encoded bytes include all source, language
and topology completeness flags, nullable source root and consumer, all source
entries, targets, products, and all 23 required empty inventory groups.

Construct private inventory values with their explicit initializers, or decode
them as part of `GeneratedPackageEvidence.decodeJSON`. Nested inventories and
blueprints do not have standalone decoding entry points. A typical library
call with already available bytes is:

```swift
let evidence = try GeneratedPackageEvidence.decodeJSON(evidenceJSON)
let result = try GeneratedPackageBlueprintAssessor().assess(
    podspecJSON: podspecJSON,
    evidence: evidence
)
let portableJSON = try result.canonicalJSON()
```

The [S1 fixture](../Tests/PkgLiftCocoaPodsTests/Fixtures/GeneratedPackageS1/README.md)
documents the synthetic declaration, caller evidence, and measured fixture
digests used to exercise this contract.

The sole reviewed provider is `pkglift.synthetic-local/v1`; this permits only
repository-owned synthetic/local evidence. Selecting that identifier is not
authentication or a provenance certificate. A production evidence provider
requires a separately reviewed profile.

The path profile `ascii-relative-path/v1` accepts only ASCII letters, digits,
underscore, dot, hyphen and slash, up to 512 bytes, with no empty, `.` or `..`
segment. This is deliberately narrower than arbitrary UTF-8. Source inventories
must be in ascending UTF-8 byte order, with no duplicate or ASCII case-fold
collision. Raw declaration order is retained for index binding. The positive
shape requires the exact `.swift` suffix plus an explicit Swift-language and
regular-file assertion. Source-root containment uses a slash-delimited prefix.

The synthetic identity grammar is `^[A-Z][A-Za-z0-9_]{0,63}$`; no name is
normalized or repaired. Package, regular target, and library-product identity
must match that Podspec name exactly. The consumer profile is `swift-only/v1`
with one Apple platform. Minimum versions use `major.minor` or
`major.minor.patch` with a nonzero patch, components of at most three digits,
positive major, and no leading zeroes. These grammars make the fixture contract
canonical; they do not claim deployment compatibility or general SwiftPM
identifier support.

`canonicalSHA256()` hashes the inventory only after validation. The byte
function is `JSONEncoder` with `.sortedKeys` and `.withoutEscapingSlashes`, no
pretty printing, and arrays already in their required order. Invalid input is
never sorted into validity. Nullable fields are encoded explicitly as `null`.
The snapshot ID digest covers its exact UTF-8 bytes. All digests are lowercase
SHA-256. Podspec identity/version comparisons use exact UTF-8 bytes.

Both evidence and result expose `decodeJSON(_:)` for untrusted bytes. This
boundary uses the existing bounded JSON scanner, rejects duplicate object keys,
and caps input at 1 MiB. A private decoder token requires every evidence,
inventory, blueprint and result decode to pass through this boundary; direct
`JSONDecoder().decode(...)` calls are rejected. Nested keys, required fields,
profile/schema versions, ordering, uniqueness, paths and digest syntax are also
checked. There are no defaults for omitted evidence fields.

S1 is capped at 256 raw or inventoried source paths, 16 targets/products and
references per product, 256 entries per empty-inventory group, and 512 bytes per
label/path. The byte scanner additionally bounds nesting, total values and
collection sizes. Before returning any result, including a noncandidate with
all its v0.5 diagnostics, the assessor checks its encoding against the same
decoder budget. A result that would exceed it throws typed `limitExceeded`.

The portable result keeps the original v0.5 assessment plus unresolved typed
reasons. A reason uses only its code and an optional numeric input index; group
indices refer to the exhaustive group-kind list in UTF-8 byte order. Canonical
reason ordering is descending outcome precedence, code, then index. For a
candidate, `dischargedReasons` equals the unchanged singleton v0.5 reason and
the `single-swift-library/v1` blueprint contains identity/version/source-root
digests, consumer context, and source references ordered by declaration index.
The raw snapshot ID, names, paths and other inventory values never enter it.

Decoded results are checked for outcome/reason agreement, the exact candidate
gate, valid profiles and digests, and contiguous unique source references. A
decoded artifact is still caller data; these checks do not authenticate its
author, bind edited artifact digests back to source inputs, establish source
existence, or authorize migration. Any consumer needing eligibility must rerun
the assessor with the original Podspec bytes and private evidence.

## Acceptance gate for Stage 1

The approved Option A implementation must provide:

1. a versioned, pure, read-only evidence model in `PkgLiftCocoaPods`;
2. one repository-owned positive `S1` fixture with documented SHA-256 values;
3. deterministic coverage for every state/reason and every negative case above;
4. decoding tests for unknown profiles, malformed paths/digests, duplicates,
   contradictions, and noncanonical ordering;
5. privacy tests proving sensitive raw evidence is absent from encoded results;
6. an isolation regression proving the new symbols do not cross into the CLI,
   registry, classifier, planner, preflight, migration, verification, Xcode, or
   `AUTO` surfaces; and
7. unchanged existing migration-plan schemas and existing v0.5 fixtures.

Even after those gates pass, the result is only a read-only structural
blueprint candidate. Manifest rendering, filesystem verification, compilation,
equivalence testing, project integration, CocoaPods removal, and migration
eligibility remain later, separately reviewed work.

## Evidence basis

The [Stage 1 validation record](GeneratedPackageStage1Validation.md) records
the completed local and integration checks. The separate
[v0.6 release evidence](GeneratedPackageV06ReleaseEvidence.md) records the
published artifact, signing, notarization and Homebrew verification.

The shipped [Podspec semantic-model contract](PodspecSemanticModel.md) defines
the pinned v0.5 profiles, raw declaration boundary, and four outcomes. The
[v0.5.0 release-evidence matrix](PodspecV05ReleaseEvidence.md) records the
complete reason-code and isolation evidence that this design must preserve.

## Decision record

- **Approved 2026-09-04:** Option A, with only the exact `S1` source-selection reason
  dischargeable in the first profile.
- **S1 limitation:** repository-owned synthetic local evidence only; no
  conventional Podspec `source` field or published-pod support.
- **Stage 1:** the API, schema and synthetic provider above are merged in `main`
  at `208ee391bd15c72289641718e60a70f62d2a1af4`; all seven integration workflows passed.
- **v0.6.0:** publicly released on 2026-09-05 through GitHub and Homebrew,
  with the exact S1 scope and separate distribution evidence linked above.
- **Later review required:** any broader provider, shape, generation or integration.
- **Never implied:** package validity, build/runtime equivalence, generation,
  project mutation, CocoaPods removal, or `AUTO`.

The released v0.5 contract remains unchanged and authoritative for declaration
assessment. Publishing v0.6.0 does not add migration support to the S1 result.
