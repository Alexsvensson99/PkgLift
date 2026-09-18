# Static public CocoaPods source evidence

This change adds a bounded static interpretation of a public specifications source.
It does not execute the Podfile or treat a matching pod name as proof of origin.

## Accepted input

Exactly one unconditional, top-level `source` invocation may name the literal
`https://github.com/CocoaPods/Specs.git`. The whole physical-line invocation must
be supported; comments and ordinary quoted literals are accepted. Multiple
sources, custom URLs, aliases, computed values, interpolations, additional
arguments, Ruby control flow and method redefinitions remain outside this slice.
The CDN spelling is not an accepted explicit source in this initial contract.

CocoaPods sources are global, and their order can affect dependency selection.
That is why recognizing `source` as harmless text would be insufficient. See the
[pinned CocoaPods source DSL](https://github.com/CocoaPods/Core/blob/38015718a35eb25d4877bc992fcbb9d0681078d5/lib/cocoapods-core/podfile/dsl.rb).

For every automatically migratable registry pod with an explicit source,
`Podfile.lock` must identify that base pod exactly once under the same exact URL
in `SPEC REPOS`. Missing, ambiguous or unsupported origin evidence cannot support
AUTO. Malformed or duplicate YAML evidence must not silently become a last-value
winner. Source URLs outside the modeled public identities are not copied into
portable analysis or plans.

## Evidence and migration

`registrySourceProvenance` is separate from external Git `sourceProvenance`.
Analysis and saved plan entries retain the supported declaration and lockfile
origin. The classifier checks their agreement, and migration compares the saved
evidence with a freshly generated current plan before writing. Changes affecting
retained dependencies must also invalidate the old source snapshot.

Projects without an explicit source retain legacy compatibility for lockfiles
that have no `SPEC REPOS`. Present unsupported origin evidence must not be
ignored. This is static consistency evidence, not attestation that installed
files came from that repository; qualification separately verifies dependency
inputs and payloads.

## Literal platform syntax

The parser also recognizes the complete literal form `platform:ios,'9.0'` as
well as the already supported spaced form. This is a syntax addition, not
permission to evaluate platform expressions or alter upstream deployment targets.
Unsupported expression tails, extra arguments, interpolation and malformed input
remain conservative.

## Real-project qualification

The selected candidate is `Suzhibin/ZBNetworking` at
[`fda54d347a0a8be11cf63e5eea76d0289e3a728d`](https://github.com/Suzhibin/ZBNetworking/tree/fda54d347a0a8be11cf63e5eea76d0289e3a728d).
Its app is a unique prospective SDWebImage 5.8.4 consumer, with AFNetworking 4.0.1
retained and two existing sibling test targets. It has a committed lockfile and
MIT license. No upstream Podfile or project edits are allowed to manufacture AUTO.

Candidate intake is not a passing G3 result. The unchanged dependency baseline,
exact AUTO set, dry-run invariance, sibling preservation, explicit dependency
refresh and equivalent post-migration builds must pass the separately reviewed
execution protocol before positive evidence can be recorded.
