# Local source inspection

Local source inspection shipped in PkgLift 0.7.0, and
[0.7.1 is published](https://github.com/Alexsvensson99/PkgLift/releases/tag/v0.7.1)
with clearer text diagnostics. This checkout develops the **unreleased 0.8
candidate**, which adds an explicit flat Swift glob mode. Its source version
remains `0.7.1` until separate release preparation.

`pkglift podspec inspect` reads a caller-supplied Podspec JSON document and a
caller-supplied local source root. Its complete result says which root source
bytes it observed, retains the original v0.5 declaration assessment, and states
what was not established. It does not prove SwiftPM compatibility, the effective
CocoaPods build inputs, source provenance, package validity, or migration
eligibility.

The [original local validation record](LocalSourceInspectionValidation.md)
describes the literal-only implementation's checks. The
[0.8 validation record](LocalSourceInspection-0.8-Validation.md) records the
completed local candidate checks and eight debug/release field-pilot comparisons.
The contract below also specifies the candidate mode; a contract is not evidence
of a published release.

## Command

Both paths are required and explicit. The command performs no project discovery,
Ruby-to-JSON conversion, CocoaPods invocation, network access, source download,
cache creation, or write in either input directory.

```text
pkglift podspec inspect --podspec <file.podspec.json> --source-root <directory>
pkglift podspec inspect --podspec <file.podspec.json> --source-root <directory> --format json
pkglift podspec inspect --podspec <file.podspec.json> --source-root <directory> --source-selection flat-swift-globs
```

Text is the default format. Both formats write the report to standard output.
Without `--source-selection flat-swift-globs`, the command retains the released
literal-only selection and byte-identical v1 JSON and text for the same inputs.
The option selects the v2 report even for a literal-only selection or a failed
inspection. Argument errors retain ArgumentParser's normal usage output; safe
typed failure codes are used for inspection failures rather than raw filesystem
diagnostics.

The filesystem boundary rejects a symlink root and every symlink component. Use
the physical absolute path for inputs in a temporary hierarchy: macOS `/tmp` and
`/var` are symlink aliases and are refused by this no-follow contract, while a
path beneath `/private/tmp` is in the physical namespace. This is intentional;
the command never resolves an alias and then opens a different path.

## Supported selection

Both modes accept only the root library's `source_files` selection. Each literal
path must be relative, end in case-sensitive `.swift`, and contain no absolute
prefix, empty component, `.` or `..` component. The default
`ascii-relative-path/v1` grammar accepts ASCII letters, digits, `_`, `.`, `-` and
`/`. The candidate mode uses the separate `ascii-relative-path/v2` grammar,
which additionally accepts literal `+` characters in directory and filename
components, such as `Sources/Constraint+Layout.swift`. A full relative path is
limited to 512 ASCII bytes in both profiles. Duplicate paths and ASCII case-fold
collisions are refused.

The default mode accepts only literal paths under its unchanged v1 grammar;
`+` remains invalid there. Every wildcard form is unsupported, even if it would
match exactly one file.

The candidate `flat-swift-globs` mode additionally accepts exactly
`<literal-relative-directory>/*.swift`. Examples are `Sources/*.swift` and
`Lib/KeychainAccess/*.swift`. There must be at least one literal directory
component; a standalone `*.swift` at the source root is unsupported.
In v2, `+` is an ordinary path character, never a wildcard or a repetition
operator. Its acceptance does not add any other pattern syntax.

| Rule | Flat Swift glob mode |
| --- | --- |
| Depth | Immediate children of the named directory only; no recursion. |
| Pattern syntax | Only the complete final component `*.swift`. No `**`, `?`, brackets, braces, escapes, prefix patterns, or wildcard directory components. |
| Matching | Case-sensitive `.swift` suffix; names beginning with `.` do not match. Each matching full path must satisfy the v2 ASCII path grammar, including literal `+`. |
| Matching entry type | A regular file is required. A matching symlink, directory, FIFO or other special entry refuses the complete observation. |
| Unmatched entries | Counted against enumeration limits. They are not read as sources, and unmatched links and subdirectories are never followed. |
| Empty match | Each glob must match at least one source; otherwise `noSourceMatches`, `unavailable`, exit 1. |
| Overlap | Literal/glob overlap, repeated matches and ASCII case-fold collisions produce `duplicateSourcePath`; there is no silent deduplication. |

All declarations are checked for syntax and selection semantics before a
successful observation can be produced. An early unsupported pattern cannot hide
a later invalid path or another selection limitation.

Subspecs, platform-scoped selectors, `exclude_files`, unknown selection semantics
and non-Swift declarations remain unsupported in both modes. Supporting a flat
glob removes only that pattern's glob limitation. Keep the original Podspec
intact: removing resources, build settings or other declarations changes what is
inspected and does not establish compatibility. No shell or general-purpose glob
expansion is used. A `.swift` suffix does not prove language semantics or
compilability.

## Filesystem observation and limits

Sources and named directories are opened relative to retained directory
descriptors without following links. File and ancestor bindings, identities and
change stamps are checked before and after reads. Each selected source and the
original Podspec are fully reread and compared by identity, byte count and content
hash during validation. Metadata alone cannot substitute for that reread.

In v2, every unique glob directory is enumerated twice, with the same limits on
both passes. The adapter compares complete entry-name/type observations and
directory bindings and stamps before and after enumeration, then rechecks the
bindings at final validation. Observed insertion, removal, rename, replacement,
unsafe type or file-content change prevents a complete result. There are no
automatic semantic retries, truncated selections or partial positive inventories.

| Budget | Limit |
| --- | ---: |
| Declared source entries | 256 |
| Selected sources after expansion | 256 |
| Bytes in one source | 16 MiB |
| Source bytes in the complete inventory | 64 MiB |
| Full relative path | 512 ASCII bytes |
| Unique glob directories (v2) | 16 |
| Entries in one glob directory, per pass (v2) | 4,096 |
| Entries across unique glob directories, per pass (v2) | 8,192 |
| Directory enumeration passes (v2) | 2 |

Enumeration counts all entries other than `.` and `..`, including entries that
do not match. Both matching and nonmatching entries can therefore exhaust a
budget. V2 enforces a separate 64 MiB source-byte budget during initial reads and
during validation rereads, including files that grow while being read: at most
128 MiB of source content is read in total. The existing separate Podspec JSON
and report-size bounds still apply. These are safety limits, not measured
performance guarantees.

The result describes observed bytes with bounded change detection. A live source
directory is **not an atomic snapshot**. A change that happens and is reversed
between observations, or happens after the last check, may remain undetected.
Even an unmatched entry's insertion, removal, rename or type change can cause
conservative refusal; unmatched file contents are not observed. Reports are not
reusable migration authorization.

## Status and exit code

| Inspection status | Meaning | Exit code |
| --- | --- | ---: |
| `verifiedObservedBytes` | Every selected supported root file was read and bound to the reported bytes. | 0 |
| `unsupportedSelection` | The document was read, but its valid root selection is outside the selected profile. | 0 |
| `unavailable` | Input, filesystem, limit, empty-match or observed-change checks prevented a complete inspection. | 1 |

Exit code 0 means that a complete report was produced. It does not mean that the
pod is SwiftPM-compatible, that a source directory came from the declared
repository, or that migration is approved. `unavailable` still writes its report
before returning 1. Unsupported and unavailable reports contain no source
inventory or complete inventory hash.

## Text presentation

Text starts with the inspection result and explains inspection reasons before
the separate declaration assessment. Reason codes remain visible. Declaration
numbers are zero-based `source_files` indexes; v2 can associate several observed
sources with one declaration. Assessment evidence paths such as
`/unsupportedFields/N` identify normalized assessment entries, not original JSON
field names. Text reports do not expose raw selected paths.

An absent inventory does not mean the project contains no source files. The
default mode retains the exact 0.7.1 presentation; v2 explains its selected
profile, match counts and bounded observation separately from the unchanged
declaration assessment.

## Report contract

| Field | Default literal-only mode | `flat-swift-globs` mode |
| --- | --- | --- |
| `schemaVersion` | `1` | `2` |
| `providerProfile` | `pkglift.local-source-inspection/v1` | `pkglift.local-source-inspection/v2` |
| `pathProfile` | `ascii-relative-path/v1` | `ascii-relative-path/v2` |
| `selectionProfile` | Omitted | `root-literals-and-flat-swift-globs/v1` |

The selected report version applies to successful, unsupported and unavailable
reports, including report-size-limit fallbacks. The existing Swift call
`inspect(podspecPath:sourceRoot:)` remains a v1 operation; a separate selection-mode
overload opts into v2.

Both versions include status, origin (`notVerified`), selection coverage
(`declaredRootSourcesOnly`), package validity (`notAssessed`), migration eligibility
(`notAssessed`), source records and typed inspection reasons. A source record
contains only its numeric declaration index, byte count, path SHA-256 and content
SHA-256. V2 orders records first by original declaration index, then by unsigned
ASCII bytes of the full relative path within each glob. Several records may
share a declaration index; there is no additional match index.

When available, the report carries the exact Podspec SHA-256, the canonical v0.5
`PodspecSwiftPMAssessment` and an inventory SHA-256. The v1 hash preimage is
unchanged. V2 hashes canonical sorted-key JSON containing exactly
`schemaVersion`, `providerProfile`, `pathProfile`, `selectionProfile`,
`podspecSHA256` and the complete ordered `sources` records. Optional fields are
omitted when unavailable. The report contains no absolute roots, raw source
paths, source URLs, author fields, source text, inode numbers, timestamps or raw
filesystem error strings. Hashes are fingerprints, not anonymization.

The declaration assessment is always made from the exact original JSON bytes;
resources, platforms, compiler controls, unknown fields and every existing v0.5
reason remain intact. File observation cannot discharge an assessment reason.
Multiple inspection limitations are retained together in deterministic order.
If the bounded report cannot retain an oversized assessment, inspection fails
with `limitExceeded` and omits that assessment instead of emitting partial evidence.

## Boundary from synthetic S1 evidence and migration

This adapter lives in the internal `PkgLiftInspection` target and is orchestrated
only by `pkglift podspec inspect`. It creates no new public package product and
does not change the pure v0.5 declaration assessors or the released v0.6 synthetic
S1 API.

Disk-derived output never uses `pkglift.synthetic-local/v1`, is not accepted as
generated-package S1 evidence, and cannot manufacture an S1 blueprint. It is not
consumed by the registry, classifier, planner, preflight, migration engine,
verification pipeline, Xcode mutation or `AUTO` eligibility.
