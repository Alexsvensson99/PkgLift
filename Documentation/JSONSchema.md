# JSON Contracts

PkgLift's machine-readable outputs are the Swift `Codable` representations of `ProjectAnalysis`, `MigrationPlan`, and `VerificationResult`. Each top-level document includes:

- `schemaVersion` (currently `1`);
- `timestamp` in ISO-8601 format;
- `pkgLiftVersion`.

These are versioned JSON contracts, not embedded JSON Schema documents: output does not contain a `$schema` property.

## Analyze

`pkglift analyze --json` writes one `ProjectAnalysis` object to stdout. It contains `project`, `cocoaPods`, `swiftPM`, `candidates`, `issues`, `readinessScore`, and an optional `counts` object. Diagnostics and SwiftPM build warnings use stderr and do not prefix the JSON document.

The explicitly named count fields distinguish literal Podfile rows from unique direct dependencies, lockfile identities, analysis candidates, and plan entries. For schema compatibility, `cocoaPods.directDependencies` remains a source-ordered list of literal declaration rows; consumers that need unique identities should use `counts.uniqueDirectDependencyCount`. A direct dependency may also contain additive `declarations` and `targetAttribution` evidence. Each declaration records its one-based Podfile line, static scope, optional scope and target names, and source kind. Target attribution records whether all declaration destinations are `exact`, `multiple`, `partial`, or `unresolved`.

Target platform and deployment values apply project xcconfig, project settings, target xcconfig, and target settings in increasing precedence. They are emitted only when the relevant values resolve statically and agree across every target build configuration; unsupported macros or conditions, unreadable include graphs, unsupported syntax, or configuration mismatches leave both fields unset. Target, SwiftPM package, and linked-product arrays are deterministically ordered.

## Plan

`pkglift plan --json` writes the same `MigrationPlan` object to stdout and `.pkglift/plan.json`. Important top-level fields are `projectPath`, `entries`, `issues`, `readinessScore`, and optional `counts`.

Repeated literal declarations of the same exact pod name are represented by one deterministic entry whose `declarations` array retains every origin. An executable AUTO entry must also contain explicit `targetAttribution` with status `exact`, one target, and no unresolved declarations. Every declaration must identify that target and use the registry source.

An executable AUTO entry contains typed actions like:

```json
[
  {
    "removePod": {
      "name": "Alamofire"
    }
  },
  {
    "addSwiftPackage": {
      "repositoryURL": "https://github.com/Alamofire/Alamofire",
      "requirement": {
        "exact": {
          "_0": "5.0.0"
        }
      }
    }
  },
  {
    "linkProduct": {
      "repositoryURL": "https://github.com/Alamofire/Alamofire",
      "productName": "Alamofire",
      "targetName": "App"
    }
  }
]
```

`migrate --apply` rejects unsupported schema or PkgLift versions and rejects entries whose action list does not exactly agree with their package, version, products, pod, target, declaration, and target-attribution metadata.

The new evidence fields are additive, so older schema-1 JSON remains decodable for inspection. Compatibility is deliberately fail-closed: an older AUTO entry without explicit declaration provenance and exact target attribution is not executable and its plan must be regenerated.

## Verify

`pkglift verify --json` writes one `VerificationResult` with `passed`, `checks`, and `issues`. A failed result still produces valid JSON but exits unsuccessfully, so CI can both parse the result and rely on the process status.

Any future incompatible representation requires a `schemaVersion` increment and migration/refusal behavior; existing fields must not be silently reinterpreted.
