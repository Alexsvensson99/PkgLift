# Local source inspection (unreleased candidate)

This document describes the local PkgLift 0.7 candidate in this source checkout.
It is not a release claim: the source version remains **0.6.2**, and no 0.7
archive, Homebrew formula, public pilot result, or migration capability is
implied by this document.

`pkglift podspec inspect` reads a caller-supplied Podspec JSON document and a
caller-supplied local source root. Its complete result says which root source
bytes it observed, retains the original v0.5 declaration assessment, and states
what was not established. It does not prove SwiftPM compatibility, the effective
CocoaPods build inputs, source provenance, package validity, or migration
eligibility.

See the [local validation record](LocalSourceInspectionValidation.md) for executed
checks, exact pilot inputs and the remaining CI/release gates.

## Command

Both paths are required and explicit. The command performs no project discovery,
Ruby-to-JSON conversion, CocoaPods invocation, network access, source download,
cache creation, or write in either input directory.

```text
pkglift podspec inspect --podspec <file.podspec.json> --source-root <directory>
pkglift podspec inspect --podspec <file.podspec.json> --source-root <directory> --format json
```

Text is the default format. Both formats write the report to standard output.
Argument errors retain ArgumentParser's normal usage output; safe typed failure
codes are used for inspection failures rather than raw filesystem diagnostics.

The filesystem boundary rejects a symlink root and every symlink component. Use
the physical absolute path for inputs in a temporary hierarchy: macOS `/tmp` and
`/var` are symlink aliases and are refused by this no-follow contract, while a
path beneath `/private/tmp` is in the physical namespace. This is intentional;
the command never resolves an alias and then opens a different path.

## Supported selection

The candidate accepts only one root-library `source_files` declaration containing
one or more canonical, relative, literal `.swift` paths. A path must use the
`ascii-relative-path/v1` grammar, be at most 512 ASCII bytes, and have no
absolute path, traversal, empty component, glob syntax, duplicate, or
case-fold collision. At most 256 sources are selected.

Each source is opened without following links and is read with an enforced
16 MiB per-file limit and 64 MiB total limit. The adapter checks the file and
directory bindings before and after reading, so a missing, replaced, changed,
special, or nonregular input is refused. A `.swift` suffix only restricts the
selection; it does not prove language semantics or compilability.

The result describes observed bytes with bounded change detection. A live source
directory is not an atomic snapshot: undetected concurrent changes or changes
after a read are not ruled out. Reports are not reusable migration authorization.

Subspecs, platform-scoped selectors, `exclude_files`, unknown selection
semantics, non-Swift sources, and all wildcard forms are outside this candidate.
A glob remains unsupported even when it would match exactly one file. No shell
or Foundation glob expansion is used.

## Status and exit code

| Inspection status | Meaning | Exit code |
| --- | --- | ---: |
| `verifiedObservedBytes` | Every selected supported root file was read and bound to the reported bytes. | 0 |
| `unsupportedSelection` | The document was read, but its valid root selection is outside this narrow profile. | 0 |
| `unavailable` | Input, filesystem, limit, or observed-change checks prevented a complete inspection. | 1 |

Exit code 0 means that a complete report was produced. It does not mean that the
pod is SwiftPM-compatible, that a source directory came from the declared
repository, or that migration is approved. `unavailable` still writes its report
before returning 1.

## Report contract

The canonical JSON report is schema version 1 and identifies the separate
`pkglift.local-source-inspection/v1` provider plus the
`ascii-relative-path/v1` path profile. It always includes the status, origin
(`notVerified`), selection coverage (`declaredRootSourcesOnly`), package-validity
status (`notAssessed`), migration-eligibility status (`notAssessed`), source
records, and typed inspection reasons. A source record contains only its numeric
declaration index, byte count, path SHA-256, and content SHA-256.

When available, the report also carries the exact Podspec SHA-256, the canonical
v0.5 `PodspecSwiftPMAssessment`, and an inventory SHA-256 that binds the profile,
Podspec digest, and complete source records. Optional fields are omitted when
unavailable. The report contains no absolute roots, raw source paths, source
URLs, author fields, source text, timestamps, or raw filesystem error strings.
Hashes are fingerprints, not anonymization.

The declaration assessment is always made from the exact original JSON bytes;
resources, platforms, compiler controls, unknown fields, and every existing v0.5
reason remain intact. File observation cannot discharge an assessment reason.
Multiple inspection limitations are retained together in deterministic order;
for example, a wildcard can coexist with unresolved Swift-version normalization.
If the bounded report cannot retain an oversized assessment, inspection fails
with `limitExceeded` and omits that assessment instead of emitting partial evidence.

## Boundary from synthetic S1 evidence and migration

This adapter lives in the internal `PkgLiftInspection` target and is orchestrated
only by `pkglift podspec inspect`. It creates no new public package product and
does not change the pure v0.5 declaration assessors or the released v0.6 synthetic
S1 API.

In particular, disk-derived output never uses `pkglift.synthetic-local/v1`, is
not accepted as generated-package S1 evidence, and cannot manufacture an S1
blueprint. It is not consumed by the registry, classifier, planner, preflight,
migration engine, verification pipeline, Xcode mutation, or `AUTO` eligibility.
