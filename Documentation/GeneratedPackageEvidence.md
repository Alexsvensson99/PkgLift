# Generated-Package Evidence Contract

Status: **v0.6 Stage 0 design candidate; documentation only.**

This document defines the evidence boundary between the released v0.5
declaration assessment and any future read-only generated-package blueprint.
It does not add a public API, bless a manifest shape, or authorize package
generation. The eligibility decision identified below must be reviewed before
implementation begins.

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

Stage 0 changes documentation only. It does not:

- add or name a public Swift type;
- read Podspec bytes or declared paths;
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
| `indeterminate` | Some evidence is unknown, deferred, opaque, incomplete, inherited, or requires inspection. | A deterministic resolution of every indeterminate reason. Stage 0 defines no positive path for this outcome. |
| `unsupported` | At least one explicit declaration is outside the pinned safe profile. | A reviewed compatibility model. Stage 0 defines no workaround or positive path for this outcome. |

A future result must carry the original v0.5 schema and profile identifiers
unchanged. It must retain the original outcome and reasons rather than emit a
second, more optimistic name for the same assessment.

## Required additional evidence

Every evidence value is caller-supplied. The future assessor may validate its
shape, internal consistency, canonical ordering, and cryptographic digest
syntax as a pure value transformation. It cannot claim that a digest matches
bytes it was never given or that an inventory matches a filesystem it never
inspected.

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

## Consistency finding: the current positive gate is impossible to use safely

The current roadmap says that `declarationCompatible` is necessary for a
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

Stage 0 therefore refuses to define a public positive result under the current
wording. This is a design finding, not a reason to weaken v0.5 or fabricate a
fixture.

## Eligibility decision required before Stage 1

### Option A — discharge one explicit metadata reason (recommended)

Preserve the v0.5 outcome and reasons exactly, but allow a future v0.6
assessment to consider one reason discharged only when the corresponding
caller-supplied evidence is complete and consistent.

The initial candidate shape, `S1`, would require:

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

This is the only option that gives `requiresGeneratedMetadata` its intended
future role without renaming it, changing the shipped v0.5 profile, or allowing
an indeterminate/unsupported reason through. It requires a small roadmap
clarification: `declarationCompatible` may remain sufficient to prove only an
empty declaration surface, while an allow-listed metadata reason may be
discharged by separately modeled evidence.

`S1` is therefore a repository-owned, synthetic local evidence slice. It can
exercise the structural contract but cannot claim support for a conventional
published Podspec, which normally carries source provenance. Supporting that
shape requires separately typed provenance semantics; the generic
`deferredCocoaPodsSemantic` reason is never dischargeable by this profile.

### Option B — retain the literal `declarationCompatible` gate

Keep the current roadmap wording unchanged. v0.6 may document missing evidence
but must ship no useful source-bearing positive blueprint, public result type,
or positive fixture. Stage 1 remains blocked until a later roadmap decision.

### Option C — weaken or rename v0.5 (rejected)

Changing the meaning of `declarationCompatible`, silently dropping the source
selection reason, or introducing a second name for the same v0.5 assessment
would invalidate a released schema/profile contract. Stage 0 rejects this
option.

Option A is the recommendation. This document records the recommendation but
does not approve it or alter the roadmap gate on its own.

## Conceptual read-only result states

These labels describe behavior for review; they are not proposed public API
names.

| State | Meaning |
| --- | --- |
| Blueprint candidate | The reviewed eligibility option is satisfied and every required evidence field for `S1` is canonical, complete, and internally consistent. This is not package validity or permission to generate. |
| Insufficient evidence | Required caller evidence is missing, incomplete, unbound, or lacks a completeness/provenance claim. |
| Contradictory evidence | Two supplied values disagree, such as identity, profile, digest binding, selection membership, language, target, or product references. |
| Ineligible shape | The Podspec or caller evidence contains a known shape outside `S1`, including subspecs, platform scopes, another declaration category, multiple targets/products, resources, dependencies, or non-Swift sources. |
| Invalid contract | Schema/profile, path, digest, canonical ordering, uniqueness, or decoding invariants are invalid. A future implementation must return a typed error before assessment. |

All observed reasons must be retained, deduplicated, and sorted
deterministically. Adding evidence may resolve a specifically modeled missing
field, but it must never erase a contradiction or make an ineligible shape
more permissive.

## Mandatory negative cases for a future implementation

| Case | Required result |
| --- | --- |
| v0.5 assessment without caller evidence | Insufficient evidence |
| Empty, duplicate, unsorted, case-colliding, or unbound source inventory | Invalid or insufficient evidence; never a candidate |
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

A future implementation must:

- use an explicit schema version and pinned CocoaPods, SwiftPM, evidence-provider,
  and path-normalization profiles;
- reject unknown profiles rather than falling forward to current behavior;
- require the canonical lowercase SHA-256 and opaque identifier grammars above;
- accept provider identifiers only from the reviewed profile registry and never
  encode a raw snapshot identifier in the assessment result;
- use immutable `Sendable`, `Equatable`, and `Codable` values;
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

## Acceptance gate for Stage 1

No public model or fixture work should begin until the eligibility option is
explicitly reviewed. If Option A is approved, Stage 1 must provide:

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

The shipped [Podspec semantic-model contract](PodspecSemanticModel.md) defines
the pinned v0.5 profiles, raw declaration boundary, and four outcomes. The
[v0.5.0 release-evidence matrix](PodspecV05ReleaseEvidence.md) records the
complete reason-code and isolation evidence that this design must preserve.

## Decision record

- **Recommended:** Option A, with only the exact `S1` source-selection reason
  dischargeable in the first profile.
- **S1 limitation:** repository-owned synthetic local evidence only; no
  conventional Podspec `source` field or published-pod support.
- **Not decided by Stage 0:** the public type names, encoded schema, evidence
  provider, or implementation schedule.
- **Blocked until review:** Stage 1 public model, fixtures, and source changes.
- **Never implied:** package validity, build/runtime equivalence, generation,
  project mutation, CocoaPods removal, or `AUTO`.

The released v0.5 contract remains authoritative until a separately reviewed
v0.6 design and implementation says otherwise.
