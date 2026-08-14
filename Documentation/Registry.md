# Dependency Registry

The registry maps a CocoaPod identifier to a verified SwiftPM repository and one or more package products. Entries are YAML files under `Registry/` and in the bundled registry resource.

```yaml
schemaVersion: 1
pod:
  name: Alamofire
swiftpm:
  repository: https://github.com/Alamofire/Alamofire
  products:
    - Alamofire
  minimumVersion: 5.0.0
migration:
  confidence: verified
metadata:
  notes: Official mapping
  lastVerified: "2026-08-14"
```

Subspec mappings add `pod.subspec`. Identifiers are exact: a base pod mapping never applies automatically to an undeclared subspec.

`swiftpm.minimumVersion` records a conservative upstream tag where the repository and listed products were verified. It must use stable `major.minor.patch` form. It is compared with the exact version resolved by `Podfile.lock`; it is never used to invent or upgrade a project version. Schema-1 mappings that omit the field remain load-compatible but are `REVIEW`-only.

## Validation

Normal analysis validates every loaded entry, including local overrides, before classification. Invalid URLs, empty products, malformed minimum versions, unsupported schema versions, or malformed YAML stop loading.

Run the full registry validation explicitly with:

```bash
swift run pkglift registry validate
```

Resolution precedence is:

1. `.pkglift/registry/` local overrides;
2. paths listed in `.pkglift.yml` under `registry.additionalPaths`;
3. the bundled registry.

The first exact pod/subspec identifier at the highest-precedence source wins.
