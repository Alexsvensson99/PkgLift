# PkgLift 0.5.0

Released 2026-09-01. PkgLift 0.5.0 adds a bounded, analysis-only Podspec JSON semantic model and a versioned SwiftPM declaration assessment. Automatic migration scope is unchanged: no Podspec declaration or assessment outcome can authorize `AUTO` or project mutation.

## Highlights

- Inspects caller-supplied, in-memory Podspec JSON under an explicit CocoaPods Core 1.17.0 semantic profile, without reading a path, executing Ruby, invoking CocoaPods, starting a process, or using the network.
- Preserves supported declarations from root, recursive library-subspec, and raw `ios`, `osx`, `tvos`, `watchos`, and `visionos` scopes with deterministic typed values and exact RFC 6901 evidence paths.
- Models platform requirements, defaults, files, headers, resources, dependencies, ordinary and weak linkage, vendored inputs, module and header layout, compilation flags, build settings, Swift versions, ARC controls, exclusions, and preserved paths.
- Assesses the bounded model against the pinned Swift tools 6.0 capability profile with schema-1 Codable output and four monotonic outcomes: `declarationCompatible`, `requiresGeneratedMetadata`, `indeterminate`, and `unsupported`.
- Includes immutable upstream and repository-authored fixtures with documented provenance and SHA-256 checksums. Together with an explicit malformed public-model regression, the release gate covers every declaration category and assessment reason across root, subspec, and platform evidence.

## Safety boundary

- `declarationCompatible` means only that no already-modeled declaration required a downgrade under the two pinned profiles. It does not prove file selection, package validity, build or runtime equivalence, or migration eligibility.
- Unknown, deferred, malformed, contradictory, opaque, dynamic, or unsupported evidence fails closed. The assessor retains every reason and selects the strongest downgrade; adding evidence cannot make an outcome more permissive.
- Dependency names, build-setting keys and values, unsupported keys, flags, source URLs, macros, and opaque paths are not copied into the assessment. Dynamically keyed evidence uses deterministic semantic-model indices.
- PkgLift does not compute CocoaPods parent inheritance or platform merging; expand globs; traverse declared paths; inspect frameworks, libraries, module maps, headers, or source files; normalize Swift versions; solve dependency requirements; or generate `Package.swift`.
- The APIs are not consumed by the CLI, registry, classifier, planner, migration preflight, migration engine, verification pipeline, or Xcode project mutation. Migration-plan schemas and all existing `AUTO` gates are unchanged.

## Compatibility and evidence

- Public semantic and assessment values are immutable, `Sendable`, `Equatable`, and `Codable`.
- Unknown CocoaPods or SwiftPM profiles return typed errors; there is no fallback to a newer behavior profile.
- Assessment decoding rejects unsupported schemas, unknown profiles or values, invalid evidence paths, duplicate or noncanonical reasons, and an outcome inconsistent with its strongest reason.
- The complete category, reason-code, fixture, regression, and release-gate record is in [PkgLift v0.5.0 Podspec Release Evidence](PodspecV05ReleaseEvidence.md).

## Upgrade notes

- The command-line interface and existing analysis/plan JSON contracts are unchanged. The public Podspec APIs are additive in the `PkgLiftCocoaPods` library module.
- Regenerate saved migration plans before applying them because executable plans remain bound to the creating PkgLift version, even though v0.5.0 does not broaden migration eligibility.
- The missing-evidence and read-only package-blueprint contract remains a separate v0.6.x concern, while manifest generation requires a later review. Consumers must not treat v0.5 assessment output as a generated manifest, compatibility certificate, registry mapping, or permission to remove CocoaPods.

This document records the shipped source and API scope. Release provenance and distribution workflows do not extend the documented migration or generation capabilities.
