# PkgLift Roadmap

PkgLift is evolving toward a comprehensive, evidence-driven dependency modernization toolkit for Apple-platform projects.

The roadmap is intentionally conservative. PkgLift will not trade migration correctness for headline compatibility numbers. Automatic migration is allowed only when PkgLift can prove that the dependency, target, version, package product, and resulting project mutation are supported and reviewable.

## Long-term goal

Automatically migrate every CocoaPods dependency that can be represented safely and equivalently in Swift Package Manager, clearly explain what cannot be migrated automatically, and preserve the project in a verifiable and recoverable state.

PkgLift is **not** aiming to claim that every CocoaPods project can be converted to pure SwiftPM. CocoaPods can express arbitrary Ruby, install hooks, scripts, private integrations, and project mutations that do not always have a deterministic SwiftPM equivalent.

## Roadmap principles

Every planned release follows these rules:

- **Safety before coverage.** A correct `REVIEW`, `BLOCKED`, or `UNKNOWN` result is better than an unsafe `AUTO` migration.
- **Evidence before heuristics.** Automatic migration requires deterministic evidence from the project, lockfile, registry, or another explicitly modeled source.
- **No hidden execution.** PkgLift does not execute arbitrary Podfile Ruby merely to increase compatibility.
- **Reviewable plans.** The saved migration plan remains the execution contract.
- **Fail closed.** Missing, stale, conflicting, or ambiguous evidence prevents mutation.
- **Real-project validation.** New automatic behavior must be exercised by fixtures and, where practical, public real-world pilots.
- **No date promises without evidence.** Planned versions describe sequence and scope, not calendar commitments.

## Status model

Roadmap items are grouped by confidence rather than by speculative release dates:

- **Released** — shipped and supported.
- **Next** — the active release target with concrete acceptance criteria.
- **Planned** — intended direction after the next release; scope may still change based on evidence.
- **Research** — technically promising work that is not yet committed to a release.
- **Long-term** — strategic goals that depend on earlier architecture and evidence.

---

# Released

## v0.1.x — Foundation

- Core **Analyze → Plan → Migrate → Verify** workflow.
- Conservative, version-gated CocoaPods-to-SwiftPM mappings.
- Typed migration actions and clean-worktree protection.
- Signed and notarized Apple Silicon distribution for macOS 14 or later.
- Homebrew installation support.

## v0.2.0 — Safer Real-Project Support

- Recursive discovery for nested Xcode projects and workspaces.
- Explicit project/workspace selection when discovery is ambiguous.
- Canonical workspace path normalization and root-containment checks.
- Literal string and symbol target syntax support without evaluating Ruby.
- Reproducible build verification with explicit scheme, configuration, destination, SDK, and derived-data settings.
- Local privacy-preserving diagnostics with deterministic JSON and secure file handling.
- Hardened, de-duplicated CI and repository-quality validation.
- Three pinned real-project classification pilots.
- A licensed positive end-to-end migration proving baseline build, reviewed apply, remaining CocoaPods integration, SwiftPM resolution, and final build.

Release evidence and the completed work breakdown are recorded in the [v0.2.0 tracker](https://github.com/Alexsvensson99/PkgLift/issues/26).

## v0.2.1 — Compatibility Evidence and Release Hardening

- Deterministic Swift, Objective-C, Objective-C++, C, and C++ target profiling from PBX metadata.
- Consumer-language evidence in the registry and a fail-closed language contract for `AUTO` and migration preflight.
- Direct Firebase Analytics, Crashlytics, and Messaging mappings at the verified `11.12.0` boundary.
- Detection and conservative refusal for Carthage plus React Native, Flutter, and Capacitor project integrations.
- Portable analyze and plan JSON with local-path and URL-secret redaction.
- Seven immutable read-only upstream pilots and one repository-owned mixed Swift/Objective-C end-to-end fixture.
- Explicit compatibility, support, and private vulnerability-reporting documentation.
- Required CI summary gates, dependency updates, and Swift code scanning before release.

---

# Next

## v0.3.0 — Broader Safe CocoaPods Coverage

**Goal:** increase the number of ordinary native CocoaPods projects that PkgLift can classify and migrate without weakening the existing safety model.

The release should focus on migration reports and recurring real-world project shapes rather than speculative ecosystem coverage.

### Planned scope

- Expand exact registry coverage for commonly encountered pods with official SwiftPM support.
- Improve static Podfile parsing for additional deterministic declarations and target structures that can be proven without evaluating arbitrary Ruby.
- Improve exact subspec handling so supported subspecs can be modeled independently without inheriting unsafe assumptions from their base pod.
- Improve reporting for why a dependency is `AUTO`, `REVIEW`, `BLOCKED`, or `UNKNOWN`, including actionable evidence requirements where possible.
- Add more reproducible real-project pilots that represent supported and intentionally refused project shapes.
- Improve CI-friendly output for migration-readiness checks without introducing mutating CI behavior.
- Preserve all current atomic migration, clean-worktree, preflight, rollback, privacy, and build-verification guarantees.

### Explicit non-goals for v0.3.0

The following are **not** required for v0.3.0:

- executing arbitrary Podfile Ruby;
- automatic conversion of `post_install` or other hooks;
- full `use_frameworks!` migration semantics;
- automatic migration of React Native, Flutter, Capacitor, or Carthage integrations;
- general Podspec-to-`Package.swift` generation;
- automatic migration of every local, Git, private, binary, Objective-C, C, or C++ pod.

### Exit criteria

v0.3.0 is ready only when all of the following are true:

- Every new `AUTO` path has positive, negative, and fail-closed fixture coverage.
- Existing v0.2.x fixtures and real-project pilots remain green.
- Every new registry mapping is backed by explicit upstream evidence and registry validation.
- Dry-run remains mutation-free.
- Applied migration remains atomic across the PkgLift mutation boundary.
- Saved-plan preflight rejects stale or changed migration evidence before the first write.
- Documentation describes every newly supported project shape and its safety boundary.
- At least three additional real-world project cases exercise the newly added behavior or demonstrate a deliberate safe refusal.
- No known high-severity migration-correctness defect remains open for the release scope.

---

# Planned

These releases describe the intended sequence after v0.3.0. Exact scope may move as real migration evidence reveals dependencies between features.

## v0.4.x — External Sources and Dependency Identity

**Goal:** model more dependency origins without guessing package identity.

Candidate work:

- Deterministic support for selected `:git` dependency declarations where repository identity and version/ref semantics can be mapped safely to SwiftPM.
- Deterministic support for selected local `:path` pods when the local specification and project layout are fully inspectable.
- Stronger source provenance in analysis and migration plans.
- Better handling of private repository URLs without leaking credentials in diagnostics or portable output.
- Expanded exact subspec and transitive-dependency modeling.

**Release boundary:** unsupported external-source behavior must remain `REVIEW`, `BLOCKED`, or `UNKNOWN`; no arbitrary source resolution is allowed.

## v0.5.x — Podspec Semantic Model

**Goal:** understand what a pod contains, not only what it is called.

Candidate work:

- Parse supported Podspec metadata into a typed semantic model.
- Model source files, public/private headers, resources, resource bundles, platform requirements, frameworks, libraries, dependencies, vendored artifacts, module maps, compiler settings, and subspec structure.
- Compare Podspec capabilities against SwiftPM capabilities.
- Report whether a pod appears natively representable, representable with generated metadata, or not safely representable.
- Keep unsupported or dynamically computed Podspec behavior fail-closed.

This milestone is an architectural prerequisite for safe generated Swift packages.

## v0.6.x — Generated Swift Package Prototype

**Goal:** prove that selected pods without native SwiftPM support can be represented safely as generated local Swift packages.

Candidate work:

- Generate a local `Package.swift` only from fully supported Podspec semantics.
- Support a deliberately narrow first set of source/resource layouts.
- Validate generated package structure before modifying the consuming Xcode project.
- Keep generated packages inside an explicit PkgLift-managed location with deterministic provenance.
- Compare the generated package against the original pod model during verification.

**Important:** this begins as an opt-in or research-grade migration path. It must not become `AUTO` until equivalence can be demonstrated reliably.

---

# Research

Research items are not release commitments. Each requires a written compatibility model, threat/safety review, fixtures, and real-project evidence before entering the planned roadmap.

## Advanced CocoaPods semantics

Investigate deterministic handling of:

- `use_frameworks!` static and dynamic linkage semantics;
- `abstract_target` and more complex inheritance graphs;
- install hooks such as `pre_install` and `post_install`;
- `script_phase` and custom build-phase behavior;
- bounded static evaluation of additional Ruby constructs without executing arbitrary project code.

PkgLift should prefer modeling effects over embedding a general Ruby execution engine.

## CocoaPods resolved-model inspection

Investigate whether an isolated, explicitly invoked CocoaPods inspection mode can expose a resolved dependency/project model safely enough to complement static parsing.

Any such design must define:

- what code is executed;
- where it is executed;
- what filesystem/network access is allowed;
- how credentials and environment variables are isolated;
- how the result is converted into reviewable evidence;
- why it does not silently weaken the existing no-arbitrary-Ruby safety model.

## Objective-C, Objective-C++, C, and C++ package generation

Investigate reliable translation of:

- header layouts;
- module maps;
- Clang settings;
- linker flags;
- system libraries;
- mixed-language target boundaries;
- generated headers and umbrella headers.

Automatic migration must remain unavailable unless every consumer language and required build behavior is represented explicitly.

## Binary and vendored dependencies

Investigate safe migration for:

- `.xcframework` artifacts;
- vendored frameworks and libraries;
- SwiftPM binary targets;
- checksum and provenance verification;
- license and redistribution constraints;
- authenticated/private artifact hosting.

## Complex dependency graphs

Develop a graph model capable of reasoning about mixed states such as:

- native SwiftPM dependencies;
- generated Swift packages;
- CocoaPods dependencies that must remain;
- transitive dependencies shared across managers;
- conflicting package requirements or product identities.

The graph solver must prefer a safe partial migration over forcing an all-or-nothing conversion.

---

# Long-term

## v1.0 — Production-Grade CocoaPods Modernization

v1.0 should represent maturity, not simply a feature count.

The target is a production-grade tool that can be given a broad range of native CocoaPods-based Xcode projects and:

1. build a deterministic dependency and target model;
2. identify everything that has a safe SwiftPM representation;
3. produce a reviewable migration plan;
4. migrate only supported items;
5. preserve unsupported CocoaPods integration where necessary;
6. verify structure and build behavior;
7. clearly explain every remaining manual decision.

### v1.0 quality bar

A future v1.0 should require, at minimum:

- a documented and stable migration-plan schema or explicit compatibility policy;
- repeatable build verification across the supported host/toolchain matrix;
- broad real-world pilot coverage across common native Xcode project shapes;
- strong rollback/recovery guidance for the full documented workflow;
- a mature registry and/or semantic evidence system with contribution validation;
- clear support boundaries for Swift, Objective-C, Objective-C++, C, and C++;
- documented behavior for partial migrations and mixed CocoaPods/SwiftPM projects;
- no known critical migration-integrity defects.

## Beyond v1.0

Possible later directions include:

- dependency-health evidence for abandoned or poorly maintained dependencies;
- vulnerability-advisory integration that remains separate from migration eligibility;
- SBOM generation;
- richer CI policy and migration-readiness automation;
- additional dependency managers only when they can be parsed, planned, mutated, and verified with the same deterministic safety model.

---

# Explicit non-goals

PkgLift does not need to become a universal package-manager replacement to succeed.

Unless the architecture changes with strong evidence, the project should not promise:

- 100% automatic conversion of arbitrary CocoaPods projects;
- arbitrary Ruby execution as a compatibility shortcut;
- silent rewriting of unsupported scripts or hooks;
- guessed package URLs, products, versions, targets, or language compatibility;
- removal of CocoaPods when unsupported dependencies still require it;
- automatic weakening of build, Git, registry, or preflight safety gates merely to increase migration counts.

A safe partial migration is a successful outcome.

# How roadmap work becomes implementation

The roadmap describes direction. Implementation should be tracked separately:

1. A roadmap release or research theme defines the outcome and safety boundary.
2. A GitHub milestone or tracking issue defines the concrete release scope.
3. Individual issues describe independently reviewable pieces of work.
4. Pull requests must link to the relevant issue or tracker and include tests/evidence appropriate to the behavior being changed.
5. Release notes record what actually shipped; unreleased roadmap candidates must not be presented as completed support.

Real migration reports may reorder planned work when they reveal a more common or higher-risk compatibility gap. The safety principles and exit criteria should not be weakened merely to keep a version number on schedule.
