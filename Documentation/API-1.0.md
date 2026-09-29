# Public API freeze for PkgLift 1.0

PkgLift 1.0 freezes the public source API exported by these six Swift package
library products:

- `PkgLiftCore`
- `PkgLiftCocoaPods`
- `PkgLiftXcode`
- `PkgLiftRegistry`
- `PkgLiftMigration`
- `PkgLiftVerification`

The `pkglift` executable and the internal `PkgLiftInspection` and
`PkgLiftSignalSupport` targets are outside this library API baseline.

## What the baseline proves

`Scripts/capture-public-api.py` loads the six already-built `.swiftmodule`
artifacts with Apple's `swift-symbolgraph-extract`. The compiler output records
public declarations, signatures, nested members, protocol requirements,
extensions and relationships such as `memberOf`. Absolute source locations are
removed, including doc-comment line positions, while doc-comment text is kept.
Symbols and relationships are sorted, and the complete normalized graphs are
retained rather than reducing the API to a list of top-level names.

The capture also records every Swift source path, byte count and SHA-256 digest
under the six targets, the aggregate source digest, each loaded module's digest,
the toolchain/SDK/target identity, and the build receipt digest. Before extraction,
every current source digest must equal a passed `build-tests` receipt whose source
inventory is unchanged before and after the build. The resolved path, size and
SHA-256 digest of every loaded module must also equal that receipt, and each module
is hashed again after extraction. Missing modules, missing sources, stale or
incomplete receipts, empty symbol graphs and compiler errors fail the capture.

This is a compiler-generated **source API inventory**, not a promise of Swift
binary ABI or module stability. PkgLift is not built with library evolution, and
the baseline does not claim cross-toolchain ABI compatibility. It is also not an
API usability test; the separate `PkgLiftPublicContractTests` compile representative
external-client calls without `@testable` imports.

The committed [module-bound build receipt](Evidence/API-1.0/local-2026-09-29-build.json)
retains portable paths plus the original local receipt digest. Its 194 build
inputs match the earlier recovery qualification; the new API graph differs only
by removal of doc-comment positions and still contains 1,931 public symbols.

## Capture and compare

Use products from the exact completed candidate build. On Alexander's Mac, all
compiler cache and temporary output must remain on the mounted `SanDisk-Arbete`
volume. First create a new module-bound receipt from the existing qualification
scratch and cache. The output directory must not exist:

```bash
python3 Scripts/build-recovery-inputs.py \
  --scratch-path /Volumes/SanDisk-Arbete/Xcode/Projects/PkgLift/Qualification-20260926/build \
  --cache-path /Volumes/SanDisk-Arbete/Xcode/SwiftPM/UserCache \
  --output /Volumes/SanDisk-Arbete/Xcode/Projects/PkgLift/OneZero-20260929/api-paired-build \
  --jobs 4 \
  --record-public-modules
```

This reuses the SwiftPM scratch for an incremental `--build-tests` check but writes
a separate receipt and logs. Existing recovery receipts and drill evidence remain
unchanged. Then capture the API from the exact product paths bound by that new
receipt:

```bash
API_ROOT=/Volumes/SanDisk-Arbete/Xcode/Projects/PkgLift/OneZero-20260929/api
mkdir -p "$API_ROOT/module-cache" "$API_ROOT/tmp"
TMPDIR="$API_ROOT/tmp" python3 Scripts/capture-public-api.py \
  --products-dir /Volumes/SanDisk-Arbete/Xcode/Projects/PkgLift/Qualification-20260926/build/out/Products/Debug \
  --build-receipt /Volumes/SanDisk-Arbete/Xcode/Projects/PkgLift/OneZero-20260929/api-paired-build/build-receipt.json \
  --symbolgraph-extract "$(xcrun --find swift-symbolgraph-extract)" \
  --sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  --target arm64-apple-macosx14.0 \
  --module-cache-path "$API_ROOT/module-cache" \
  --include-path /Volumes/SanDisk-Arbete/Xcode/Projects/PkgLift/Qualification-20260926/build/checkouts/Yams/Sources/CYaml/include \
  --output Documentation/Evidence/API-1.0/public-api.json
```

The output path must be new. To compare a later build without overwriting the
baseline, replace the last line with:

```bash
  --check Documentation/Evidence/API-1.0/public-api.json
```

Comparison fails when any compiler-emitted public surface digest changes. A
source-only implementation change is reported but does not fail API comparison;
the new build receipt must still bind those new source bytes. A toolchain update
can change symbol-graph serialization, so its baseline diff must be reviewed and
the compiler/SDK fields updated deliberately.

## Versioning policy after 1.0

- Removing a public declaration, narrowing visibility, changing a public
  signature, conformance, generic constraint or availability, or otherwise
  breaking source compatibility requires a new major version.
- Compatible public additions use a minor release. Compatible fixes that do not
  add public API use a patch release.
- Deprecate public API before removal when practical, with a replacement and a
  migration note. Deprecation does not by itself authorize removal in a minor or
  patch release.
- Every release candidate compares compiler output against the accepted baseline.
  An intentional additive change updates the baseline in the same reviewed change;
  an intentional breaking change also updates the major version and migration
  documentation.

The baseline is therefore a review gate and provenance record. It does not turn
every source hash change into an API break, and it does not replace a public
consumer compilation test.
