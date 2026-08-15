# Distribution

PkgLift v0.1.1 and later is distributed for Apple Silicon on macOS 14 or later.
The public archive must contain a Developer ID-signed, Apple-notarized executable
and the adjacent `PkgLift_PkgLiftRegistry.bundle` resource directory.

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

- A manual `workflow_dispatch` run from `main` signs, notarizes, verifies a
  freshly extracted quarantine-marked CLI, and uploads a private Actions
  artifact. It never creates a GitHub Release. Manual runs from other refs are
  skipped.
- A `v*` tag runs the same package job and creates a GitHub Release only after
  every validation has passed and the `production-release` environment is
  approved. Tags outside `origin/main` are refused.
- A final v0.2.0 tag must match the CLI version (`v0.2.0`); prerelease tags may
  append a suffix such as `v0.2.0-rc.1`.
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
bash Scripts/scaffold-homebrew-tap.sh /tmp/homebrew-tap 0.2.0 VERIFIED_SHA256
```

The command refuses to overwrite an existing path and creates the tap README,
formula, and CI workflow. The v0.2.0 `Formula/pkglift.rb` contract is:

```ruby
class Pkglift < Formula
  desc "Safely migrate CocoaPods dependencies to Swift Package Manager"
  homepage "https://github.com/Alexsvensson99/PkgLift"
  url "https://github.com/Alexsvensson99/PkgLift/releases/download/v0.2.0/pkglift-macos-arm64.tar.gz"
  version "0.2.0"
  sha256 "REPLACE_WITH_VERIFIED_RELEASE_SHA256"
  license "MIT"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    libexec.install "pkglift", "PkgLift_PkgLiftRegistry.bundle"
    bin.install_symlink libexec/"pkglift"
  end

  test do
    assert_equal "0.2.0", shell_output("#{bin}/pkglift version").strip
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

Creating the final tag, creating the GitHub Release, and publishing the formula
require explicit approval after the private distribution artifact has passed all
acceptance checks.
