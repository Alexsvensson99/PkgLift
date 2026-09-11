# PkgLift 0.7.0 — Local Podspec source inspection

PkgLift can inspect the bytes selected by a supported local JSON Podspec:

```sh
pkglift podspec inspect --podspec Example.podspec.json --source-root ./Example --format json
```

The command accepts explicit inputs and emits text or deterministic JSON. Literal
root Swift source selections produce bounded file and inventory digests. Reports
preserve the original declaration assessment and distinguish observed bytes,
unsupported selection semantics and unavailable input. Completed reports exit 0;
unavailable input exits 1.

## Safety and limits

The reader rejects symlink paths, traversal, case collisions, unsafe file types,
oversized inputs and observed replacements. It does not expand globs or execute
Ruby, upstream code or network requests. Failed observations never expose a
partial source inventory. Mutable directories are observed bytes, not a guaranteed
atomic snapshot against a hostile concurrent writer.

This feature does not prove source origin, effective CocoaPods build inputs,
SwiftPM package validity or migration eligibility. It does not supply synthetic
S1 evidence, generate a package or broaden registry classification or `AUTO`.
See the [command contract](LocalSourceInspection.md) for exact limits and outcomes.

## Verification and compatibility

The implementation passed 501 tests locally and in PR #96 on Xcode 16.4 / Swift
6.1.2. Debug and optimized builds, registry validation, pinned and mixed-language
pilots, repository checks and CodeQL all passed for that implementation. Three
pinned upstream inputs and one controlled local fixture produced their expected,
repeatable reports without changing inputs. See the
[historical local validation record](LocalSourceInspectionValidation.md).

The source version is `0.7.0`. Regenerate saved migration plans after upgrading;
plans remain bound to the PkgLift version that created them.

Local source-preparation checks on 2026-09-09 also passed all 501 tests, the
optimized build, registry validation for 22 mappings, 26 release-policy tests and
repository YAML validation. The 0.7.0 optimized executable repeated all four
local pilot cases with unchanged inputs and correct unavailable-input exit 1.

## Release status

This is source preparation for an unreleased candidate. The version-preparation
commit still requires its own CI. Signed and notarized artifacts, a release
manifest, public tag and GitHub Release, and Homebrew distribution remain subject
to the [distribution gates](Distribution.md). No release manifest is included here.
