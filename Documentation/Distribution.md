# Distribution

PkgLift v0.1.1 and later is distributed for Apple Silicon on macOS 14 or later.
The public archive must contain a Developer ID-signed, Apple-notarized executable
and the adjacent `PkgLift_PkgLiftRegistry.bundle` resource directory.

[PkgLift v0.6.0](https://github.com/Alexsvensson99/PkgLift/releases/tag/v0.6.0)
was published on 2026-09-05 and is available through the Homebrew tap. The
[release evidence](GeneratedPackageV06ReleaseEvidence.md) records its exact
source commit, public checksum and completed distribution checks.

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
- A manual `workflow_dispatch` run from `main` signs, notarizes, verifies a
  freshly extracted quarantine-marked CLI, and uploads a private Actions
  artifact. It never creates a GitHub Release. Manual runs from other refs are
  skipped.
- Direct tag pushes never start a distribution or publication workflow. The
  reviewed release-manifest workflow is the only path that creates a public tag
  and GitHub Release.
- A final tag must match the CLI version exactly (for example, CLI `0.6.0`
  requires tag `v0.6.0`); prerelease tags may append a suffix such as
  `v0.6.0-rc.1`.
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
bash Scripts/scaffold-homebrew-tap.sh /tmp/homebrew-tap 0.6.0 VERIFIED_SHA256
```

The command refuses to overwrite an existing path and creates an initial tap
README, formula and CI workflow. Remove the scaffold's explicit `version`
stanza when Homebrew can infer the version from the URL; strict audit rejects
the redundant stanza. The published v0.6.0
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

Creating the release-manifest branch, merging its reviewed commit, approving
the protected publication environment, creating the final tag and GitHub
Release, and publishing the formula all require explicit approval after the
private distribution artifact has passed every acceptance check. Do not add a
new release manifest to the product-preparation commit.
