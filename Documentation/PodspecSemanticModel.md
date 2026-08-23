# Podspec JSON Semantic Inspection

Status: **v0.5.0 development, analysis-only**

PkgLift can inspect a deliberately bounded subset of an already available
`.podspec.json` document through `PkgLiftCocoaPods`:

```swift
let inspection = try PodspecJSONInspector().inspect(json: data)
```

The API accepts in-memory `Data` only. It does not read a path or URL, execute a
Ruby podspec, invoke CocoaPods, resolve a glob, start a process, or contact a
repository. Callers are responsible for deciding where the bytes came from.

## Modeled declarations

The first implementation slice requires non-empty string `name` and `version`
fields and models these optional root fields:

- `platforms`, including `ios`, `osx`, `tvos`, `watchos`, and `visionos`;
- `source_files`;
- `public_header_files` and `private_header_files`;
- `resources`;
- `resource_bundles`.

Path-pattern fields accept CocoaPods' string or array-of-strings JSON forms.
PkgLift preserves their order and contents, including globs and traversal-like
segments, but never expands or opens them. Resource-bundle names and platforms
are normalized into deterministic arrays.

Common descriptive fields such as `summary`, `description`, `homepage`,
`license`, and `authors` are explicitly non-semantic in this model. Recognized
but deferred CocoaPods behavior, including dependencies, subspecs, frameworks,
libraries, vendored artifacts, module maps, compiler settings, script phases,
platform-specific blocks, and source provenance, is reported as
`deferredCocoaPodsSemantic`. Other fields are reported as `unknownField`.
Every report uses an escaped RFC 6901 JSON Pointer and is sorted
deterministically.

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
enforces the structural limits and rejects duplicate object keys, including
keys that become equal after decoding Unicode escapes. Malformed values,
duplicate keys, and exceeded limits return `PodspecInspectionError`. There are
no force unwraps or fatal errors at this boundary. Custom limits are validated
before input can reach the scanner or semantic model. A custom nesting limit
may be lowered or raised only through the absolute recursion ceiling of 128.

## Safety boundary

An empty `unsupportedFields` array means only that this bounded parser modeled
the declarations it was asked to inspect. It does **not** prove that:

- CocoaPods and SwiftPM select the same files or resources;
- headers, modules, linkage, compiler settings, or transitive dependencies are
  equivalent;
- a native or generated Swift package can build the pod;
- a registry mapping is correct;
- a dependency is eligible for `AUTO`.

The inspector is not connected to the CLI, registry, classifier, planner,
preflight, project mutation, or verification pipeline. Package generation
remains a separate v0.6.x concern. Release work is tracked in
[#63](https://github.com/Alexsvensson99/PkgLift/issues/63).

Pinned test fixtures are documented in
[`Tests/PkgLiftCocoaPodsTests/Fixtures/PodspecJSON/README.md`](../Tests/PkgLiftCocoaPodsTests/Fixtures/PodspecJSON/README.md).
