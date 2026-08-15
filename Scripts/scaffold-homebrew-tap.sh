#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <output-directory> <version> <archive-sha256>" >&2
  exit 64
fi

output_directory="$1"
version="$2"
archive_sha256="$3"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must use stable semantic version form, for example 1.2.3." >&2
  exit 64
fi

if [[ ! "$archive_sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Archive SHA-256 must contain exactly 64 lowercase hexadecimal characters." >&2
  exit 64
fi

if [[ -e "$output_directory" ]]; then
  echo "Refusing to overwrite existing tap path: $output_directory" >&2
  exit 73
fi

mkdir -p "$output_directory/Formula" "$output_directory/.github/workflows"

cat > "$output_directory/Formula/pkglift.rb" <<'FORMULA'
class Pkglift < Formula
  desc "Safely migrate CocoaPods dependencies to Swift Package Manager"
  homepage "https://github.com/Alexsvensson99/PkgLift"
  url "https://github.com/Alexsvensson99/PkgLift/releases/download/v__VERSION__/pkglift-macos-arm64.tar.gz"
  version "__VERSION__"
  sha256 "__SHA256__"
  license "MIT"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    libexec.install "pkglift", "PkgLift_PkgLiftRegistry.bundle"
    bin.install_symlink libexec/"pkglift"
  end

  test do
    assert_equal "__VERSION__", shell_output("#{bin}/pkglift version").strip
    system bin/"pkglift", "registry", "validate"
  end
end
FORMULA

sed -i '' \
  -e "s/__VERSION__/$version/g" \
  -e "s/__SHA256__/$archive_sha256/g" \
  "$output_directory/Formula/pkglift.rb"

cat > "$output_directory/README.md" <<'README'
# Homebrew Tap for PkgLift

Install the latest signed and notarized Apple Silicon release of PkgLift:

```bash
brew install Alexsvensson99/tap/pkglift
```

PkgLift supports macOS 14 or later. Source code and release notes are available
in the [PkgLift repository](https://github.com/Alexsvensson99/PkgLift).
README

cat > "$output_directory/.github/workflows/test.yml" <<'WORKFLOW'
name: Test Formula
on:
  push:
    branches: ['**']
  pull_request:

jobs:
  test:
    runs-on: macos-15
    permissions:
      contents: read
    env:
      HOMEBREW_NO_AUTO_UPDATE: '1'
      HOMEBREW_NO_INSTALL_FROM_API: '1'
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6
      - name: Configure Local Tap
        run: brew tap --custom-remote Alexsvensson99/tap "$GITHUB_WORKSPACE"
      - name: Style
        run: brew style Alexsvensson99/tap/pkglift
      - name: Audit
        run: brew audit --strict --online Alexsvensson99/tap/pkglift
      - name: Install
        run: brew install Alexsvensson99/tap/pkglift
      - name: Test
        run: |
          cd /tmp
          pkglift version
          pkglift registry validate
          brew test Alexsvensson99/tap/pkglift
      - name: Uninstall
        if: always()
        run: brew uninstall pkglift || true
WORKFLOW

echo "Created Homebrew tap scaffold at $output_directory"
