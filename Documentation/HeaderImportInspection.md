# Header imports before automatic migration

PkgLift reads a bounded set of consumer files when analyzing an Xcode target:
its compiled C, C++, Objective-C and Objective-C++ source references, local quoted
header imports reachable from them, and literal prefix/bridging headers found in
project and target configurations (including xcconfigs). No compiler, package
manager, source generator or project script runs during this inspection.

The target source profile has an additive optional `headerImports` field:

| Value | Meaning | Automatic migration |
| --- | --- | --- |
| `clear` | No blocking import was found within the supported inspection | Other registry, language, platform and provenance gates still apply |
| `requiresReview` | A flat angle import/include or unresolved quoted header may depend on existing header search paths | Refused |
| `incomplete` | Inputs could not be inspected safely or syntax/settings are unsupported | Refused |
| absent | Legacy evidence or a Swift-only target without observed header inputs | Refused for any C-family target |

`#import <SDImageCache.h>` and `#include <SDImageCache.h>` require review.
Module-qualified forms such as `#import <SDWebImage/SDWebImage.h>` do not trigger
that finding. Quoted local headers are followed only relative to the including
file; a header requiring another search path is conservatively reviewed.
Conditional branches are inspected without evaluating the preprocessor.
Comments are ignored, and standard line continuations are joined.

This policy intentionally also reviews flat system includes such as `<stdio.h>`.
PkgLift does not infer ownership from a header basename, consult an SDK allowlist,
or assert that all flat includes are broken. The finding affects every mapped
dependency of that exact target, because header ownership is not proven. Other
targets' source files are not used to infer that target's import status.

Unreadable or missing compiled files, nonregular inputs, symlinks, path escapes,
unknown includes/macros, unsupported compiler flags, unresolved header settings,
and exhausted bounds prevent clear evidence. Fresh nonempty target profiles require concrete
matching project and target configuration metadata. Every configuration is
considered conservatively, including values a target might override. Swift-only
legacy language profiles remain decodable; observed prefix/bridging header risks
still prevent automatic migration.

Limits per target: 1 MiB per file, 16 MiB total, 512 files and 32 local-header
recursion levels. Cycles terminate. Descriptor-relative regular-file reads reject
symlinks and verify file metadata across the read. Only the fixed status is
serialized: no source text, file names, paths or header names are added to reports.

`clear` is a bounded risk check, not evidence that SwiftPM compilation will pass.
Qualified imports and platform module availability still require real build
verification. PkgLift does not rewrite imports, restore removed Pod headers or
add header-search-path workarounds.

The classifier emits `target_header_imports_require_review` or
`target_header_import_evidence_incomplete`. Plans with either state contain no
automatic actions for the affected dependency. Migration preflight independently
requires admissible header evidence, rejects legacy C-family AUTO entries, and
compares saved evidence with freshly analyzed target profiles before writes.

## Verification

The unchanged pinned ZBNetworking consumer at `fda54d347a0a8be11cf63e5eea76d0289e3a728d`
now reports SDWebImage REVIEW with `target_header_imports_require_review`.
The app target reports `requiresReview`; its two test targets report `clear`.
The upstream working tree remains clean after read-only analysis. See the
[local validation receipt](Evidence/MultiTargetQualification-1.0/zb-header-import-review.json).
This does not close the positive G3 qualification.

Local checks: 395 XCTest tests, 233 Swift Testing tests, 257 Python policy tests,
25 registry mappings and repository YAML validation passed. Build and Swift tests
used the existing SwiftPM `native` cache after the default `swiftbuild` engine
failed its test-bundle signing step on filesystem metadata. Independent review
found no remaining material blocker.
