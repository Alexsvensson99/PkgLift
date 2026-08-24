# Podspec JSON Semantic Inspection

Status: **v0.5.0 development, analysis-only**

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

## Recursive declaration model

`PodspecSemanticModel.root` is an immutable recursive `PodspecNode`. Each node
records:

- its complete CocoaPods identity, local base name, and RFC 6901 object path;
- its own `platforms` deployment declarations;
- its own unexpanded file, header, resource, resource-bundle, dependency,
  linkage, module, header-layout, and vendored-input declarations;
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
  metadata, vendored inputs, `static_framework`, and supported platform blocks;
- **descriptive**: metadata such as `summary`, `description`, `homepage`,
  `license`, and `authors` at their valid root scope, which is deliberately
  excluded from this semantic model;
- **deferred**: recognized CocoaPods behavior such as build settings, compiler
  flags, scripts, source provenance, test specs, and app specs; or
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
remains a separate v0.6.x concern. Release work is tracked in
[#63](https://github.com/Alexsvensson99/PkgLift/issues/63).

Pinned and repository-authored test fixtures are documented in
[`Tests/PkgLiftCocoaPodsTests/Fixtures/PodspecJSON/README.md`](../Tests/PkgLiftCocoaPodsTests/Fixtures/PodspecJSON/README.md).
