# Distribution

PkgLift v0.1.1 and later uses an Apple Silicon/macOS 14 distribution minimum.
For 1.0, the lowest observed exact signed-artifact runtime is macOS 14.8.9
(23J631); deployment metadata and Homebrew `:sonoma` do not prove exact 14.0.
The public archive must contain a Developer ID-signed, Apple-notarized executable
and the adjacent `PkgLift_PkgLiftRegistry.bundle` resource directory.

[PkgLift v1.0.1](https://github.com/Alexsvensson99/PkgLift/releases/tag/v1.0.1)
is the current public release. GitHub published release ID `401431070` at
`2026-10-01T23:31:14Z` (`2026-10-02` Europe/Stockholm), with tag `v1.0.1`
targeting M, `030b8a21d936a96e76090ca39ac78dd68c4df51c`. The downloaded
public archive SHA-256 is
`eaee546af04f11df66d1f16cbbbf66dea881969e0dd34795d1a5b74e65b9e591`,
its binary SHA-256 is
`b7409899d57ed6e90c4afaa11c46e29da85a889eb5ec7028189191c2c4cb8173`,
and its registry-bundle tree SHA-256 is
`14e6d8975c87f7ad88b6d92bd43319662db9a43893f134ca0000abf0234e5510`.
The immutable [1.0.1 Homebrew formula](https://github.com/Alexsvensson99/homebrew-tap/blob/0f1faf8805b00c575f1989075235b3609c89a7ea/Formula/pkglift.rb)
at commit `0f1faf8805b00c575f1989075235b3609c89a7ea` uses that same public archive.
See [1.0.1 release notes](ReleaseNotes-1.0.1.md), the
[complete qualification](Qualification-1.0.1.md) and the
[observed environment evidence](Environments-1.0.md#101-maintenance-evidence-2026-10-02).

### 1.0.1 publication evidence

- Final source F, `76dd1f9712f9e5da3609bacc26e0d0022e2ae290`, was prepared by
  [PR #142](https://github.com/Alexsvensson99/PkgLift/pull/142). Manifest-only
  [PR #143](https://github.com/Alexsvensson99/PkgLift/pull/143) made M its sole
  direct child and bound it to successful exact-F main pilot run
  [36764966069](https://github.com/Alexsvensson99/PkgLift/actions/runs/36764966069).
- [G3 source run 36765095908](https://github.com/Alexsvensson99/PkgLift/actions/runs/36765095908)
  passed the named AWS partial migration and mutation-protected FirebaseUI and
  Hammerspoon refusals on F. The
  [source receipt](Evidence/Qualification-1.0.1/source-qualification.json)
  also binds the local 655 Swift tests, 300 policy tests and unchanged six-module
  API result.
- [Exact M release run 36769614583](https://github.com/Alexsvensson99/PkgLift/actions/runs/36769614583),
  attempt 1, passed signing/notarization, full/partial/refusal consumer acceptance
  and the observed macOS 14 runtime. The cloud and
  [local M acceptance](Evidence/Qualification-1.0.1/local-final-M-acceptance.json)
  use the exact public archive, binary and registry-bundle hashes above.
- Protected publication run
  [36769590339](https://github.com/Alexsvensson99/PkgLift/actions/runs/36769590339)
  completed successfully. The
  [public readback](Evidence/Qualification-1.0.1/public-distribution.json) binds
  exact M, release ID `401431070`, both downloadable assets, strict signature,
  version `1.0.1`, 25 registry mappings and the accepted candidate bytes.
- [Homebrew PR #18](https://github.com/Alexsvensson99/homebrew-tap/pull/18)
  merged at `2026-10-01T23:46:19Z` as
  `0f1faf8805b00c575f1989075235b3609c89a7ea`. The formula Git blob is
  `87d540096631337027fa06cbffb65569360e8fbe` and its SHA-256 is
  `544ef889e0b6970360136cc6c220e5df3ecd193896744d3a86900c86b7470b47`.
  [PR CI 36942357174](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/36942357174)
  on `aacff2e56f4dc6a317610da82de921e79a49c99f` and
  [main CI 36942559400](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/36942559400)
  on the merge commit, both attempt 1, passed Apple Silicon, local-tap setup,
  style, audit, install, installed verification, formula test and uninstall.
  Local syntax, style and diff checks passed; no local install or audit was
  performed for 1.0.1, and no system components were changed.

### 1.0.0 publication evidence

- Final source F, `1839cbfe614c3affeecd6c790bb43ca2053a334a`, was prepared by [PR #138](https://github.com/Alexsvensson99/PkgLift/pull/138).
  [PR #139](https://github.com/Alexsvensson99/PkgLift/pull/139) added only the reviewed manifest, making M its sole direct child.
- [Exact M Release run](https://github.com/Alexsvensson99/PkgLift/actions/runs/36615292778) passed signing/notarization,
  full/partial/refusal consumer acceptance and the observed macOS 14 runtime.
  [Local M acceptance](Evidence/Qualification-1.0/local-final-M-acceptance.json) separately passed core runtime and four consumer flows on macOS 27/Xcode 27 before production approval.
- [Protected publication](https://github.com/Alexsvensson99/PkgLift/actions/runs/36615269741) and the
  [public readback](Evidence/Qualification-1.0/public-distribution.json) bind tag, downloadable archive/checksum and extracted binary.
- [Homebrew PR](https://github.com/Alexsvensson99/homebrew-tap/pull/17), [PR CI](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/36619218315)
  and [main CI](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/36619431921) verify the clean hosted install/test/uninstall lifecycle,
  qualifying the formula update separately from GitHub publication. Both runs passed.
- Local formula style passed. Local `brew audit --strict --online` stopped on
  outdated Command Line Tools before any local install. No system components
  were changed and no local Homebrew lifecycle success is claimed.

The [0.10.0 release notes](ReleaseNotes-0.10.0.md) retain their historical
bounded CryptoSwift qualification.

[PkgLift v0.9.0](https://github.com/Alexsvensson99/PkgLift/releases/tag/v0.9.0)
was published at `eaecabf570d06ccff905ef45723c5e49d126c0ba`.
Its [release notes](ReleaseNotes-0.9.0.md) remain the historical record for the
KeychainAccess and DeviceKit release scope.
The [v0.6 release evidence](GeneratedPackageV06ReleaseEvidence.md) remains a
historical record of that release's checks.

## Release credentials

The release workflow requires a Developer ID Application certificate exported as
a password-protected P12 file and an App Store Connect API key authorized for
notarization. Store only the encoded credential material in GitHub Actions
secrets; never commit the certificate, private key, API key, or decoded files.

Create a protected GitHub Actions environment named `distribution-signing`,
require maintainer approval for deployments to it, and configure these
environment secrets:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer team identifier |
| `DEVELOPER_ID_APPLICATION_IDENTITY` | Full `Developer ID Application: ...` identity |
| `DEVELOPER_ID_P12_BASE64` | Base64-encoded P12 certificate and private key |
| `DEVELOPER_ID_P12_PASSWORD` | Password used when exporting the P12 file |
| `NOTARY_ISSUER_ID` | App Store Connect API issuer identifier |
| `NOTARY_KEY_ID` | App Store Connect API key identifier |
| `NOTARY_KEY_P8_BASE64` | Base64-encoded API private key |

The workflow decodes credentials only into the runner's temporary directory,
imports the certificate into an ephemeral keychain, and removes both after the
job even when validation fails.

Create a second protected environment named `production-release` with required
maintainer approval and no signing secrets. Only the job that uploads validated
artifacts to a public GitHub Release receives `contents: write` permission.

## Workflow contract

- Prepare and merge the complete product release first. Then create a separate
  branch whose only repository change is one newly added, reviewed
  `.github/releases/vX.Y.Z.json` manifest. That manifest commit must be the
  push's only commit and the single direct child of the source-preparation
  commit on `main`. Its `sourcePreparationCommit`
  must equal the merged preparation PR's final commit, and its
  `positivePilotWorkflowRun` must identify the successful
  `Mixed-Language End-to-End Pilot` push run for that exact commit on `main`.
- When that manifest reaches `main`, `Publish Reviewed Release Manifest`
  verifies that the complete push diff contains only the newly added manifest.
  It also verifies the exact schema, source version, dated changelog, current
  main head, fast-forward ancestry, merged preparation PR, successful positive
  pilot evidence, and absence of an existing tag. It then dispatches the signed
  distribution workflow for that exact manifest-only `main` SHA, waits for
  success, rechecks the artifact checksum, and pauses at the protected
  `production-release` environment. After approval it rechecks the current
  `main` ref, atomically creates the exact lightweight tag with fail-if-exists
  semantics, verifies that tag's target, and only then creates the public
  release.
- Restarting manifest validation first attaches to an active distribution for
  the exact repository, commit, main branch and release workflow. Otherwise it
  reuses a successful run only when the expected nonexpired artifact exists.
  With neither available, it checks current main and dispatches once. After a
  dispatch, historical run IDs cannot satisfy the wait; the selected run ID and
  attempt remain fixed. API errors, ambiguous new runs, changed identity and
  selected-run failures stop validation rather than trigger another dispatch.
  History discovery is bounded to 1,000 runs and fails if that bound is reached.
  Artifact contents and checksums are still checked downstream, and both
  protected approval environments remain in force. Concurrent manual dispatches
  are not an atomic transaction with this lookup; multiple visible new matches
  are refused. An uncertain dispatch response is never automatically retried.
- A manual `workflow_dispatch` run from `main` signs and notarizes the package,
  then verifies the freshly extracted, quarantine-marked CLI against the
  recorded archive and executable hashes. A dependent consumer-acceptance job
  with read-only permissions and no signing secrets downloads those exact bytes
  and exercises
  a complete supported migration through apply and build, a partial migration
  that retains CocoaPods dependencies through apply and build, and a
  conservative refusal that must leave the fixture unchanged. A dependent
  Apple Silicon macOS 14 job downloads that exact private artifact, records the
  observed host patch/build and CPU, and repeats the bounded runtime and
  structural-apply checks without compiling a consumer. The workflow must succeed in full before the
  manifest workflow can publish. Manual runs never create a GitHub Release,
  and runs from other refs are skipped.
- Direct tag pushes never start a distribution or publication workflow. The
  reviewed release-manifest workflow is the only path that creates a public tag
  and GitHub Release.
- A final tag must match the CLI version exactly (for example, CLI `1.0.0`
  requires tag `v1.0.0`); prerelease tags may append a suffix such as
  `v1.0.0-rc.1`.
- The notarization ZIP is a temporary submission format. Public releases contain
  only `pkglift-macos-arm64.tar.gz` and its `.sha256` file.

`spctl` returns exit 3 for a valid standalone Mach-O executable because it is
not a top-level app bundle. The workflow therefore accepts only that exact
"valid code, but not an app" classification, and only after `notarytool`
returned `Accepted` and the extracted executable passed strict `codesign`
verification for the expected Developer ID authority, team identifier,
hardened runtime flag, and secure timestamp. The quarantine-marked CLI must
then execute, report the expected version, and validate its adjacent registry
bundle.

Run the non-signing packaging checks locally with:

```bash
swift build -c release -j 2 --arch arm64
bash Scripts/package-release.sh release /tmp/pkglift-release
```

The script verifies that the tarball preserves the built executable byte for
byte, targets arm64 and macOS 14, passes checksum validation, loads its registry
both directly and through an installed-style symlink, and reports a typed error
when the registry bundle is absent.

## Homebrew tap

The public tap is `Alexsvensson99/homebrew-tap`. After the GitHub Release exists,
update the formula with the exact public archive SHA-256. For a new tap checkout,
the scaffold command is:

```bash
bash Scripts/scaffold-homebrew-tap.sh /tmp/homebrew-tap VERSION VERIFIED_SHA256
```

The command refuses to overwrite an existing path and creates an initial tap
README, formula and CI workflow. Remove the scaffold's explicit `version`
stanza when Homebrew can infer the version from the URL; strict audit rejects
the redundant stanza. The historical v0.6.0 example
[`Formula/pkglift.rb`](https://github.com/Alexsvensson99/homebrew-tap/blob/35431a6351c3242d75296262201682ee77475153/Formula/pkglift.rb)
is:

```ruby
class Pkglift < Formula
  desc "Safely migrate CocoaPods dependencies to Swift Package Manager"
  homepage "https://github.com/Alexsvensson99/PkgLift"
  url "https://github.com/Alexsvensson99/PkgLift/releases/download/v0.6.0/pkglift-macos-arm64.tar.gz"
  sha256 "87533df993ab31af4764eb4c15734b06a3a64364dd493d042a9b7d16333f4088"
  license "MIT"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    libexec.install "pkglift", "PkgLift_PkgLiftRegistry.bundle"
    bin.install_symlink libexec/"pkglift"
  end

  test do
    assert_equal "0.6.0", shell_output("#{bin}/pkglift version").strip
    system bin/"pkglift", "registry", "validate"
  end
end
```

Before publishing the formula, run:

```bash
brew style Alexsvensson99/tap/pkglift
brew audit --strict --online Alexsvensson99/tap/pkglift
brew install Alexsvensson99/tap/pkglift
brew test Alexsvensson99/tap/pkglift
pkglift version
pkglift registry validate
brew uninstall pkglift
```

The protected signing and publication environments still require their
configured approvals. The release operator must also have current authorization
for the complete publication and Homebrew update. Those controls do not replace
the artifact checks, and an authorization does not permit bypassing a failed
gate. Do not add a new release manifest to the product-preparation commit.
