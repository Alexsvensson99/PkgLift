# JSON Contracts

PkgLift's machine-readable outputs are the Swift `Codable` representations of `ProjectAnalysis`, `MigrationPlan`, and `VerificationResult`. Each top-level document includes:

- `schemaVersion` (currently `1`);
- `timestamp` in ISO-8601 format;
- `pkgLiftVersion`.

These are versioned JSON contracts, not embedded JSON Schema documents: output does not contain a `$schema` property.

## Analyze

`pkglift analyze --json` writes one `ProjectAnalysis` object to stdout. It contains `project`, `cocoaPods`, `swiftPM`, `candidates`, `issues`, and `readinessScore`. Diagnostics and SwiftPM build warnings use stderr and do not prefix the JSON document.

## Plan

`pkglift plan --json` writes the same `MigrationPlan` object to stdout and `.pkglift/plan.json`. Important top-level fields are `projectPath`, `entries`, `issues`, and `readinessScore`.

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

`migrate --apply` rejects unsupported schema or PkgLift versions and rejects entries whose action list does not exactly agree with their package, version, products, pod, and target metadata.

## Verify

`pkglift verify --json` writes one `VerificationResult` with `passed`, `checks`, and `issues`. A failed result still produces valid JSON but exits unsuccessfully, so CI can both parse the result and rely on the process status.

Any future incompatible representation requires a `schemaVersion` increment and migration/refusal behavior; existing fields must not be silently reinterpreted.
