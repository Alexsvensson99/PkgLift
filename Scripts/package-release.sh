#!/usr/bin/env bash

set -euo pipefail

configuration="${1:-release}"
output_directory="${2:-release}"
archive_name="pkglift-macos-arm64.tar.gz"
checksum_name="${archive_name}.sha256"
bundle_name="PkgLift_PkgLiftRegistry.bundle"

binary_directory="$(swift build -c "$configuration" --show-bin-path)"
binary_path="${binary_directory}/pkglift"
bundle_path="${binary_directory}/${bundle_name}"

if [[ ! -x "$binary_path" ]]; then
  echo "Missing release executable: $binary_path" >&2
  exit 1
fi

if [[ ! -d "$bundle_path" ]]; then
  echo "Missing registry resource bundle: $bundle_path" >&2
  exit 1
fi

mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd)"
staging_directory="$(mktemp -d)"
smoke_directory="$(mktemp -d)"

cleanup() {
  rm -rf "$staging_directory" "$smoke_directory"
}
trap cleanup EXIT

cp "$binary_path" "$staging_directory/pkglift"
cp -R "$bundle_path" "$staging_directory/$bundle_name"

tar -czf "$output_directory/$archive_name" \
  -C "$staging_directory" \
  pkglift \
  "$bundle_name"

(
  cd "$output_directory"
  shasum -a 256 "$archive_name" > "$checksum_name"
)

tar -xzf "$output_directory/$archive_name" -C "$smoke_directory"
file "$smoke_directory/pkglift" | grep -q "arm64"
(
  cd "$smoke_directory"
  ./pkglift registry validate
)

mkdir -p "$smoke_directory/bin"
ln -s "$smoke_directory/pkglift" "$smoke_directory/bin/pkglift"
(
  cd /tmp
  "$smoke_directory/bin/pkglift" registry validate
)

echo "Created and smoke-tested $output_directory/$archive_name"
