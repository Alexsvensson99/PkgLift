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
migration:
  confidence: verified
metadata:
  notes: Official mapping
```

Subspec mappings add `pod.subspec`. `swiftpm.minimumVersion` is optional metadata; it is not used to invent a version when the analyzed dependency lacks deterministic version evidence.

## Validation

Normal analysis validates every loaded entry, including local overrides, before classification. Invalid URLs, empty products, unsupported schema versions, or malformed YAML stop loading.

Run the full registry validation explicitly with:

```bash
swift run pkglift registry validate
```

Resolution precedence is:

1. `.pkglift/registry/` local overrides;
2. paths listed in `.pkglift.yml` under `registry.additionalPaths`;
3. the bundled registry.

The first exact pod/subspec identifier at the highest-precedence source wins.
