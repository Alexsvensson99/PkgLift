# PkgLift 1.0.0 — Verified, conservative migration contracts

Status: **source preparation, 2026-09-29; not published.** The current public
GitHub download and Homebrew formula remain 0.10.0 until the exact 1.0 candidate
passes the protected distribution workflow and public readback. No final release
commit, tag, archive checksum, observed macOS 14 patch or Homebrew pull request is
known at source-preparation time.

## What 1.0 establishes

PkgLift 1.0 freezes the documented meanings of its public CLI commands and
options, JSON reports and plans, reason codes, configuration and registry
schemas, and six public Swift library products. Additive report fields remain
possible. Breaking changes require the documented deprecation and major-version
policy.

Saved plans are executable evidence, not portable instructions for a different
binary. A plan created by an earlier PkgLift version must be regenerated with
1.0.0 before dry run or apply. Do not edit its producer version, classification
or evidence fields.

Version 1.0 also includes the safety work prepared but never publicly released
as 0.11.0:

- bounded registry-source and C-family header-import evidence;
- typed refusal for missing, unsupported, conflicting or incomplete evidence;
- no-follow, binding-checked and atomically replaced `.pkglift/plan.json` writes;
- stricter target attribution, retained-CocoaPods validation and executable-plan
  freshness checks;
- preservation checks for unrelated schemes, breakpoints, source, resources and
  existing SwiftPM integration.

PkgLift still does not rewrite imports, execute arbitrary Podfile Ruby, invent
package metadata, migrate local or external Git pods, run `pod install`, or turn
an uncertain dependency into `AUTO`.

## Initial positive support envelope

The 1.0 positive qualification claim is intentionally narrower than everything
PkgLift can discover or safely refuse. It covers the exact mapping, target,
language, platform and version combinations backed by the candidate evidence
matrix, including the repository-owned complete and partial migration fixtures
and any named single-target case requalified with the exact candidate.

A positive external multi-target or workspace migration is explicitly deferred
from the initial 1.0 envelope. PkgLift retains project/workspace discovery,
explicit selection, target attribution, sibling preservation and conservative
refusal behavior for those shapes, but 1.0 does not present a repository fixture
or a refusal as an external positive success. That deferred cell remains
post-1.0 qualification work.

Automatic migration remains conditional on complete live evidence. `REVIEW`,
`BLOCKED` and `UNKNOWN` are successful safety outcomes when the contract cannot
justify a write.

## Runtime and toolchain evidence

The release remains Apple Silicon-only. Historical runs observed the released
CLI on macOS 14.8.9, source and consumer workflows with Xcode 16.4/Swift 6.1.2,
and local source checks with Xcode 27/Swift 6.4. Those are separate observed
cells, not proof of every intermediate or later toolchain.

The final 1.0 runtime floor is recorded only after the exact signed candidate
runs on the selected Apple Silicon macOS 14 runner. The resulting OS patch and
build are evidence for the host actually observed; source preparation does not
claim that exact macOS 14.0 was exercised. Consumer builds remain bound to their
recorded Xcode, Swift, SDK, CocoaPods, scheme, configuration and destination.

## Exact-candidate release acceptance

The protected release workflow builds, tests, signs and notarizes the candidate,
then binds all acceptance to the freshly extracted archive and signed binary
hashes. Before it can become a successful release run, that exact candidate must:

1. pass strict Developer ID, hardened-runtime, timestamp, notarization,
   quarantine, version and bundled-registry checks;
2. complete the reviewed mixed Swift/Objective-C migration and build;
3. complete a partial migration that retains the non-automatic CocoaPods
   dependency and passes the fresh post-migration build;
4. produce the reviewed conservative refusal without changing the selected
   upstream project or Git index; and
5. pass the hash-bound Apple Silicon macOS 14 runtime check, including analysis,
   planning, inert dry run and structural apply on a disposable repository fixture.

The macOS 14 job downloads the signed artifact from the same workflow run. Its
failure prevents the overall release workflow from succeeding and therefore
prevents manifest publication. Private acceptance evidence is stored separately;
the public release archive still contains only `pkglift` and its adjacent registry
bundle.

## Upgrade guidance

After installing the published 1.0 release, confirm the executable and bundled
registry before creating a new plan:

```bash
pkglift version
pkglift registry validate
pkglift analyze
pkglift plan
pkglift migrate
```

Review the complete plan and keep the worktree clean before separately choosing
`pkglift migrate --apply`. Refresh dependencies that remain under CocoaPods with
your normal reviewed `pod install` process, then run structural and build
verification using the project's explicit scheme and destination.

## Publication status

This document is part of source preparation. It does not prove a signed
candidate, protected-environment approval, public `v1.0.0` tag, GitHub Release,
Homebrew update or live website state. Those facts must be added or verified from
the actual release runs and public assets; no placeholder SHA or checksum is used
here.
