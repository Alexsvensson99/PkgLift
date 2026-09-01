# Podspec JSON Semantic Inspection

Status: **released in v0.5.0; analysis-only**

PkgLift can inspect a deliberately bounded subset of an already available
`.podspec.json` document through `PkgLiftCocoaPods`:

```swift
let inspector = PodspecJSONInspector(
    semanticProfile: .cocoaPodsCore1_17_0
)
let inspection = try inspector.inspect(json: data)
```

The API accepts in-memory `Data` only. It does not read a path or URL, execute a
Ruby podspec, invoke CocoaPods, resolve a glob, start a process, or contact a
repository. Callers are responsible for deciding where the bytes came from.

## Version-bound semantics

Podspec JSON has no schema or generator-version field. PkgLift therefore makes
the interpretation profile explicit and currently supports exactly
`cocoapods-core/1.17.0`. Any other `CocoaPodsSemanticProfile` returns
`PodspecInspectionError.unsupportedSemanticProfile` before the document is
decoded. A pod's `cocoapods_version` declaration does not select the profile;
that requirement remains deferred.

The initial profile is pinned to CocoaPods Core
[`1.17.0`](https://github.com/CocoaPods/Core/releases/tag/1.17.0), commit
[`f14b9a21f3aacd771c1eb9b099910d33a6d2cce0`](https://github.com/CocoaPods/Core/commit/f14b9a21f3aacd771c1eb9b099910d33a6d2cce0).
Its supported forms follow Core's tagged
[`Specification::JSONSupport`](https://github.com/CocoaPods/Core/blob/1.17.0/lib/cocoapods-core/specification/json.rb),
[`Specification`](https://github.com/CocoaPods/Core/blob/1.17.0/lib/cocoapods-core/specification.rb),
and
[`Specification::DSL`](https://github.com/CocoaPods/Core/blob/1.17.0/lib/cocoapods-core/specification/dsl.rb).

## Versioned SwiftPM declaration assessment

An already completed inspection can be compared with one explicit SwiftPM
capability profile:

```swift
let assessment = try PodspecSwiftPMAssessor().assess(
    inspection,
    cocoaPodsProfile: .cocoaPodsCore1_17_0,
    swiftPMProfile: .swiftToolsVersion6_0
)
```

`PodspecSwiftPMAssessment` is schema version 1 and records both caller-supplied
profiles. The initial SwiftPM profile identifier is
`swift-tools-version/6.0`. Unknown CocoaPods or SwiftPM profiles return a typed
`PodspecSwiftPMAssessmentError`; there is no fallback to the latest behavior.
The supplied CocoaPods profile must also equal the profile embedded in the
inspection. Decoding an assessment additionally rejects an unknown schema,
unknown profile, noncanonical reason order, duplicate reason, invalid evidence
path, or outcome that does not match its strongest reason.

The outcome order, from most to least permissive, is:

| Outcome | Declaration-level meaning |
| --- | --- |
| `declarationCompatible` | No modeled declaration requires a downgrade under the pinned profile. |
| `requiresGeneratedMetadata` | A known declaration category needs explicit future package metadata. |
| `indeterminate` | Unknown, deferred, opaque, incomplete, or uninspected evidence prevents a capability conclusion. |
| `unsupported` | The pinned safe profile does not support at least one explicit declaration category. |

The assessor evaluates every piece of evidence and selects the strongest
downgrade. Adding unknown, deferred, contradictory, or unsupported evidence
therefore cannot make an outcome more permissive. All reasons are retained,
deduplicated, and sorted first by downgrade strength, then by stable reason
code and canonical evidence locator.

The initial profile deliberately treats root-level source/header/resource
selection, dependency declarations, ordinary linker settings, module/header
layout, linkage mode, exclusions, and platforms as future generated metadata.
Subspec and platform-scope inheritance remains indeterminate because the
semantic model intentionally preserves those declarations without computing
CocoaPods' effective merge. Vendored artifacts, custom module maps, and literal
Swift versions are also indeterminate because this layer does not inspect
files, artifact formats, or version semantics. Weak frameworks, disabled
module maps, compiler flags, xcconfig settings, configuration-specific
dependencies, ARC controls, and preserved paths are unsupported by this safe
profile. A future profile may change capabilities only under a new explicit
identifier.

Each `PodspecSwiftPMAssessmentReason` contains a typed `code` and a canonical,
privacy-bounded `evidencePath` that uses RFC 6901 escaping rules. It is an
assessment locator, not a promise that the string can be dereferenced in the
original Podspec JSON. Statically named declarations retain familiar field
paths. Dynamically keyed maps such as dependencies and build settings use a
deterministic semantic-model index instead of copying their key text. Unknown
and deferred fields similarly use their stable `/unsupportedFields/<index>`
slot in the caller-owned inspection. The assessment also never copies a
corresponding declaration value. An attacker-controlled key, flag,
credential-bearing source URL, macro, or local path can therefore remain in
the inspection without being duplicated into the assessment artifact.

The assessment is a pure value transformation. It does not read Podspec bytes,
the filesystem, environment variables, repositories, or the network; expand
globs; start a process; resolve dependencies; or generate `Package.swift`. It
is not consumed by the CLI, registry, classifier, planner, preflight, migration
engine, or `AUTO` eligibility.

Most importantly, `declarationCompatible` means only that the bounded,
already-modeled declaration categories did not require a downgrade. It is
**never** proof of file selection, package validity, source, resource, linkage,
language, build, or runtime equivalence.

## Recursive declaration model

`PodspecSemanticModel.root` is an immutable recursive `PodspecNode`. Each node
records:

- its complete CocoaPods identity, local base name, and RFC 6901 object path;
- its own `platforms` deployment declarations;
- its own unexpanded file, header, resource, resource-bundle, dependency,
  linkage, module, header-layout, vendored-input, compilation, build-setting,
  ARC, and file-selection declarations;
- separate raw `ios`, `osx`, `tvos`, `watchos`, and `visionos` declaration
  scopes;
- its child library subspecs in source-array order; and
- an explicit or implicit default-subspec policy.

The original flat properties such as `name`, `sourceFiles`, and
`resourceBundles` remain compatibility projections of the root's global
declarations. The recursive tree is authoritative.

Object-based collections are normalized deterministically: platforms use a
fixed Apple-platform order, while dependency names and resource-bundle names
are sorted. JSON arrays retain their declared order. All model types are
immutable, `Sendable`, `Equatable`, and `Codable`; the encoded model includes
the semantic profile. Byte-stable JSON additionally requires a configured
encoder such as `JSONEncoder.outputFormatting = [.sortedKeys]`.

### Dependencies

The supported CocoaPods Core 1.17.0 form is an object whose values are arrays
of literal requirement strings:

```json
{
  "dependencies": {
    "Networking/Core": ["~> 4.0", "< 5.0"],
    "Unconstrained": []
  }
}
```

PkgLift records each dependency, requirement literal, and exact escaped JSON
pointer. It preserves requirement-array order and accepts the empty array, but
does not parse operators, apply CocoaPods' default requirement, solve versions,
or translate requirements to SwiftPM. Scalar, null, object, non-string, and
empty-string requirement forms fail with a typed path-specific error.

Dependencies can be declared globally on any node and inside any supported
platform scope. Those declarations remain separate. The profile does not
materialize CocoaPods' parent inheritance or global-plus-platform hash merge.

### Linkage, modules, headers, and vendored inputs

The pinned profile models these raw forms:

| Declaration | Accepted JSON | Accepted raw scopes |
| --- | --- | --- |
| `frameworks`, `weak_frameworks`, `libraries` | non-empty string or array of non-empty strings | root, subspec, and their platform blocks |
| `vendored_frameworks`, `vendored_libraries` | non-empty opaque path string or array of them | root, subspec, and their platform blocks |
| `header_dir`, `header_mappings_dir` | one non-empty opaque string | root, subspec, and their platform blocks |
| `project_header_files` | non-empty opaque path string or array of them | root, subspec, and their platform blocks |
| `module_name` | one non-empty string | root global scope only |
| `module_map` | `true`, `false`, or one non-empty opaque path string | root global scope and root platform blocks |
| `static_framework` | a literal JSON boolean | root global scope only |

Each scalar or array element is retained with its exact escaped RFC 6901 path.
Arrays preserve order and duplicates. An absent list and an explicit empty
array both produce no literal elements; neither is interpreted as effective
behavior. Empty or whitespace-only strings fail at the field or element path.
`module_map: true` and `module_map: false` have distinct typed states for
default generation and disabling, while a string remains an opaque custom
path. A numeric `0` or `1` is not accepted as a JSON boolean.

CocoaPods Core 1.17.0 declares `module_map` as root-only but still
multi-platform, so `/ios/module_map` and the other root platform forms are
modeled separately from `/module_map`. This behavior follows the pinned Core
[`DSL`](https://github.com/CocoaPods/Core/blob/1.17.0/lib/cocoapods-core/specification/dsl.rb#L1534-L1564)
and
[`PlatformProxy`](https://github.com/CocoaPods/Core/blob/1.17.0/lib/cocoapods-core/specification/dsl/platform_proxy.rb#L31-L41);
PkgLift does not compute which value a CocoaPods consumer would inherit. A
`module_map` under any subspec, including a subspec platform block, is rejected
as outside the root-only contract. `module_name` and `static_framework` are
non-platform root attributes and are rejected in every child or platform
scope.

There is no Podspec `static_library` attribute in CocoaPods Core 1.17.0. A JSON
key with that name is therefore retained as `unknownField` evidence instead of
being given invented semantics or combined with `static_framework`. Duplicate
JSON keys, including duplicate modeled declarations, remain typed conflicts at
the bounded JSON grammar boundary. Simultaneous global and platform values are
separate raw declarations, not a conflict, and no additional conflict rule is
invented for declarations that CocoaPods Core permits.

All strings in this group are data, not filesystem capabilities. PkgLift does
not traverse `..`, follow a symlink, expand a glob, open an archive, inspect a
binary, infer a file kind from `.framework`, `.xcframework`, `.a`, or `.dylib`,
or claim that any declaration is a SwiftPM binary target.

### Compilation and file selection

The pinned profile also models these raw declaration forms:

| Declaration | Accepted JSON | Accepted raw scopes |
| --- | --- | --- |
| `compiler_flags` | non-empty string or array of non-empty strings | root, subspec, and their platform blocks |
| legacy `xcconfig`, `pod_target_xcconfig`, `user_target_xcconfig` | object whose keys are non-empty strings and whose values are strings | root, subspec, and their platform blocks |
| `configuration_pod_whitelist` | object mapping same-scope dependency names to arrays containing only `debug` and `release` | root and subspec global scopes, never platform blocks |
| `swift_versions` | non-empty string or array of non-empty strings; the array may be explicitly empty | root global scope only |
| legacy `swift_version` | one non-empty string | root global scope only |
| `requires_arc` | JSON boolean, non-empty pattern string, or array of non-empty pattern strings | root, subspec, and their platform blocks |
| `exclude_files`, `preserve_paths` | non-empty string or array of non-empty strings | root, subspec, and their platform blocks |

List entries and build-setting values retain exact escaped RFC 6901 paths.
Object entries are sorted by key for deterministic output; declared arrays
retain order, duplicates, and explicit emptiness. Build-setting values may be
empty because emptiness is itself literal data. Keys and values such as
`$(inherited)`, `$(SRCROOT)`, shell-looking text, path traversal, and glob
characters are preserved byte-for-byte as strings. They are never expanded,
interpolated, evaluated, written to an xcconfig, or passed to a process.

The legacy `xcconfig` object remains separate from both target-specific
objects. Although the Ruby DSL setter copies that value into
`pod_target_xcconfig` and `user_target_xcconfig`, loading Podspec JSON stores
the raw hash directly. PkgLift therefore does not reproduce the setter,
merge maps, or invent precedence.

`configuration_pod_whitelist` is CocoaPods Core's serialized representation
of dependency `:configurations`. Every map key must name a dependency declared
in the same node scope and every value must be an array of the lowercase
literal strings `debug` and `release`; the empty array remains explicit. Core's
platform dependency proxy does not create this map, so a whitelist inside a
platform block is rejected rather than assigned speculative semantics.

CocoaPods JSON commonly contains both `swift_versions` and its generated
backwards-compatibility `swift_version`. PkgLift preserves the plural values,
plural declaration path, and legacy singular separately. Their typed
relationship is `exactMatch` only when the plural declaration is non-empty and
every plural literal equals the singular byte-for-byte. Otherwise it is
`requiresCocoaPodsNormalization`, and both declaration paths are retained as
`deferredCocoaPodsSemantic` evidence. CocoaPods converts the combined values to
versions, deduplicates and sorts them, then serializes the last version as the
legacy singular. PkgLift deliberately defers every pair with more than one
distinct literal, even when the singular occurs in the plural list, because it
cannot prove the generated counterpart without reproducing that normalization
and selection. Deferred cases also include spelling variants such as `5` and
`5.0`, a separately supplied legacy value, or a singular value paired with an
explicitly empty plural array. The document remains inspectable, but the
unresolved pair cannot be treated as positive capability evidence. PkgLift does
not parse, normalize, sort, deduplicate, or compare version numbers. Both keys
are root-only and non-platform under the pinned DSL.

An ARC boolean is retained as a boolean; ARC file patterns are retained as
opaque literals. PkgLift does not apply CocoaPods' default, determine which
source files require ARC, add compiler flags, expand `exclude_files`, protect
`preserve_paths`, or inspect any path. Global, child, and platform values stay
in their original `PodspecScopedDeclarations` and are never inherited or
merged.

### Subspecs and defaults

`subspecs` must be a recursive array of objects with non-empty local names.
PkgLift composes identities such as `Root/Group/Leaf`, preserves every node's
source path, and rejects slash-bearing or otherwise invalid identity
components. Duplicate sibling names fail with
`duplicateSubspecIdentity`; they are never collapsed or selected by
first-match behavior.

The root accepts the current `default_subspecs` key and legacy singular
`default_subspec`. Supported values are:

- one name string;
- an array of name strings;
- the canonical `"none"` value, plus the unambiguous compatibility form
  `["none"]`; or
- an empty array, which has CocoaPods' implicit-all policy.

With no declaration, the model also records the implicit-all policy. Named
defaults are resolved case-sensitively against the declared library-subspec
hierarchy without creating dependency edges. A missing, malformed, repeated,
or ambiguous reference fails at its exact path. Supplying both default keys or
mixing `none` with names also fails closed. Defaults are root-only and are
rejected inside subspec or platform scopes.

### Raw scopes and indeterminate effective behavior

PkgLift never combines a node's declarations with its parent or with a
platform block in this slice. A modeled child relationship therefore adds
`deferredCocoaPodsSemantic` evidence at the child's object path, and a modeled
platform scope adds the same evidence at the platform-block path. This makes
the unavailable effective inheritance or merge result visible even when every
declaration inside the scope is otherwise typed.

These markers do not mean the raw declarations were discarded. They mean only
that CocoaPods' effective consumer view was intentionally not guessed.

## Field classification

Every direct key at root, subspec, and supported platform depth is handled as
one of four categories:

- **modeled**: identity, recursive subspecs, defaults, platforms, dependencies,
  file/header/resource declarations, resource bundles, linkage/module/header
  metadata, vendored inputs, compilation flags, xcconfig maps, configuration
  whitelists, Swift-version declarations, ARC controls, file selection,
  `static_framework`, and supported platform blocks;
- **descriptive**: metadata such as `summary`, `description`, `homepage`,
  `license`, and `authors` at their valid root scope, which is deliberately
  excluded from this semantic model;
- **deferred**: recognized CocoaPods behavior such as scripts, hooks, computed
  commands, source provenance, test specs, and app specs; or
- **unknown**: keys outside the recognized contract for that scope.

Deferred and unknown evidence is retained in `unsupportedFields` with exact,
escaped RFC 6901 pointers and deterministic ordering. A known modeled field
with the wrong JSON shape throws a typed error rather than being downgraded to
unknown evidence. Root-only descriptive metadata encountered in a subspec or
platform block is retained as deferred scope-invalid evidence rather than
silently ignored.

## Trust-boundary limits

The default inspector limits are:

| Limit | Default |
| --- | ---: |
| JSON input | 1,048,576 bytes |
| Nesting depth | 64 |
| Elements in one object or array | 4,096 |
| Values in the complete document | 16,384 |
| One UTF-8 string or object key | 65,536 bytes |

Before Foundation materializes an object graph, a bounded JSON grammar scan
enforces all structural limits and rejects duplicate object keys, including
keys that become equal after decoding Unicode escapes. The same scan bounds
recursive subspecs, dependencies, and platform scopes before semantic
recursion. Malformed values, duplicate keys, and exceeded limits return
`PodspecInspectionError`. There are no force unwraps or fatal errors at this
boundary. A custom nesting limit may be raised only through the absolute
recursion ceiling of 128.

## Safety boundary

An empty `unsupportedFields` array means only that this bounded parser modeled
the declaration forms it was asked to inspect. It does **not** prove that:

- CocoaPods parent inheritance or platform merging has been evaluated;
- CocoaPods and SwiftPM select the same files, resources, or dependencies;
- raw headers, modules, linkage, vendored inputs, compiler settings, or
  transitive dependencies are effective or equivalent;
- a native or generated Swift package can build the pod;
- a registry mapping is correct; or
- a dependency is eligible for `AUTO`.

The inspector is not connected to the CLI, registry, classifier, planner,
preflight, project mutation, or verification pipeline. Package generation
remains a separate future concern. The completed v0.5.0 implementation work is
tracked in [#63](https://github.com/Alexsvensson99/PkgLift/issues/63).

Pinned and repository-authored test fixtures are documented in
[`Tests/PkgLiftCocoaPodsTests/Fixtures/PodspecJSON/README.md`](../Tests/PkgLiftCocoaPodsTests/Fixtures/PodspecJSON/README.md).
The complete declaration, reason-code, regression, and release-gate matrix is
recorded in [`Documentation/PodspecV05ReleaseEvidence.md`](PodspecV05ReleaseEvidence.md).
