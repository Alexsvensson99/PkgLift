# Unsupported project format guard — local verification

The format-conversion defect found during the [maintenance review](MaintenanceReview-2026-09-29.md)
is fixed and verified locally. This change is **unreleased**. PR #133's reviewed
head still lacks the fix; its old green checks are not integration approval.
The source branch keeps XcodeProj 9.16.0 in `Package.resolved`.

## Behavior

A shared package-scoped guard rejects any immediate `.xcproj` entry in the
selected project bundle, including JSON-only projects, simultaneous PBX/JSON
definitions, case variants, and dangling links. Project-directory symlinks are
resolved before checking. Existing PBX filename and parse behavior remain.

The analyzer checks before reading unsupported data or producing migration
evidence. The editor checks before opening and again immediately before a
write. The migration engine also checks before Podfile or recovery-state writes
for direct library callers, preserving the existing incomplete-recovery and
cancellation checks first. Structural verification inherits the analyzer's
refusal. The typed diagnostic is internal; public error enums and API signatures
are unchanged. These checks do not claim atomicity against arbitrary concurrent
filesystem changes.

## Verification

All local runs used Apple Silicon macOS 27.0 (26A428), Xcode 27.0 / Swift 6.4.

| Check | Result |
| --- | --- |
| Full suite with release pin XcodeProj 9.16.0 | 655 passed: 422 XCTest + 233 Swift Testing |
| Full suite with exact PR #133 lockfile update to 9.17.5 | The same 655 passed |
| Compiler-emitted public API | All six library modules match the frozen 1.0 baseline |
| Registry validation | All 25 mappings passed |
| Repository YAML and patch whitespace | Passed |
| Independent source/test review | No remaining actionable finding |

The permanent CLI tests embed the exact explicit- and implicit-type JSON
fixtures from the original reproduction, without depending on newer conversion
APIs. Each first generates a real registry-backed AUTO plan from the supported
PBX fixture, then changes the project format and commits clean Git input state.
Analyze, plan, dry run, verify and apply all refuse the unsupported project;
original bytes and saved plans remain unchanged, and no recovery backup or
second project definition is created. Separate tests cover editor entry points,
case variants, links, pre-write engine refusal and recovery-marker priority.

The earlier failing probe remains historical evidence. It is not a current
failure: its explicit-type case established the defect before the guard;
permanent tests now assert refusal on those same JSON bytes.

Candidate and final build-input inventories differ only in `Package.resolved`.
The final paired build records 197 unchanged inputs and the exact public modules
used for the API comparison. The [portable receipt](Evidence/Postrelease-2026-09-29/format-guard-verification.json)
contains input and raw-evidence hashes. Build caches, paired artifacts, API output,
logs and explicitly routed new fixture data are on the development SSD. Existing
Swift/XCTest framework temporary-directory behavior is not a new storage guarantee.

No remote workflows, consumer Xcode builds, signing, release or Homebrew updates
were run for this fix. Hosted Xcode 16.4 and protected current-base integration
checks remain required before merging an updated dependency PR. The fix does not
add JSON project migration support or external multi-target qualification.
