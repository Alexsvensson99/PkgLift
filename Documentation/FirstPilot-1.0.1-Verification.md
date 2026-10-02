# First-pilot guide verification — PkgLift 1.0.1

Checked on 2026-10-02. This record verifies the [first-pilot guide](FirstPilot.md)
using the published 1.0.1 binary on the repository-owned `PartialSwift` fixture.
It is a documentation command check, not an external user report or a completed
migration. The [portable receipt](Evidence/FirstPilot-1.0.1.json) records the
commands, hashes, fixture identity and separate installation/baseline evidence.

## What was checked

- `pkglift version` returned `1.0.1`; registry validation passed all 25 mappings.
- A fresh, committed fixture copy began with empty Git status.
- Analysis selected `SwiftKeychainAccess.xcodeproj` and the intended target.
- Plan review confirmed exactly one `AUTO` entry: KeychainAccess 4.2.2, its exact
  package/product, and the `SwiftKeychainAccess` target. SDWebImage 5.18.1 stayed
  `BLOCKED` by the fixture's explicit retention policy.
- `pkglift migrate --path .` ran in its default dry-run mode. No `--apply` was
  supplied. Working-tree and staged diff checks passed.
- All nine original fixture files remained byte-identical. Only
  `.pkglift/plan.json` was added; it is expected untracked planning output.

The local command check ran on Apple Silicon macOS 27.0 (26A428). Its binary
SHA-256 was `b7409899d57ed6e90c4afaa11c46e29da85a889eb5ec7028189191c2c4cb8173`,
from the public archive with SHA-256
`eaee546af04f11df66d1f16cbbbf66dea881969e0dd34795d1a5b74e65b9e591`.

## Separate evidence and limits

Homebrew installation was verified in [tap PR #18](https://github.com/Alexsvensson99/homebrew-tap/pull/18)
and its successful [PR](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/36942357174)
and [main](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/36942559400)
lifecycle checks: install, version, bundled registry, signature, formula test
and uninstall. Those checks used the same public archive. This local guide
check did not install Homebrew or PkgLift through Homebrew again.

The fixture's successful CocoaPods baseline build is reused from the
[exact 1.0.1 local acceptance](Evidence/Qualification-1.0.1/local-final-M-acceptance.json).
The fixture tree hash still matches that record. No new baseline build, package
installation, apply, app launch or simulator launch was performed for this
command check. The guide's baseline-build prerequisite still applies to a
user's own project.

Installation, prior baseline qualification and this fresh command check are
separate observations. They do not establish a single new end-to-end install/build
run, an external pilot, or positive external multi-target/workspace support.
