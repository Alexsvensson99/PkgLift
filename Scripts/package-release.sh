#!/usr/bin/env bash

set -euo pipefail

configuration="${1:-release}"
output_directory="${2:-release}"
architecture="${PKGLIFT_ARCH:-arm64}"
archive_name="pkglift-macos-arm64.tar.gz"
checksum_name="${archive_name}.sha256"
notarization_name="pkglift-macos-arm64-notarization.zip"
bundle_name="PkgLift_PkgLiftRegistry.bundle"

binary_directory="$(swift build -c "$configuration" --arch "$architecture" --show-bin-path)"
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
notarization_smoke_directory="$(mktemp -d)"
missing_bundle_directory="$(mktemp -d)"

cleanup() {
  rm -rf \
    "$staging_directory" \
    "$smoke_directory" \
    "$notarization_smoke_directory" \
    "$missing_bundle_directory"
}
trap cleanup EXIT

cp "$binary_path" "$staging_directory/pkglift"
cp -R "$bundle_path" "$staging_directory/$bundle_name"

if [[ "${PKGLIFT_REQUIRE_DEVELOPER_ID:-0}" == "1" ]]; then
  if [[ -z "${PKGLIFT_EXPECTED_TEAM_ID:-}" ]]; then
    echo "PKGLIFT_EXPECTED_TEAM_ID is required for Developer ID packaging." >&2
    exit 1
  fi
  codesign --verify --strict --verbose=4 "$staging_directory/pkglift"
  codesign -dvvv "$staging_directory/pkglift" 2> "$staging_directory/codesign-details.txt"
  if ! grep -q "Authority=Developer ID Application:" "$staging_directory/codesign-details.txt" \
    || ! grep -q "TeamIdentifier=${PKGLIFT_EXPECTED_TEAM_ID}" "$staging_directory/codesign-details.txt" \
    || ! grep -Eq 'flags=.*runtime' "$staging_directory/codesign-details.txt" \
    || ! grep -Eq '^Timestamp=' "$staging_directory/codesign-details.txt"
  then
    echo "Release executable is not a timestamped Developer ID binary for team ${PKGLIFT_EXPECTED_TEAM_ID}." >&2
    cat "$staging_directory/codesign-details.txt" >&2
    exit 1
  fi
  rm "$staging_directory/codesign-details.txt"
fi

(
  cd "$staging_directory"
  /usr/bin/zip -qry "$output_directory/$notarization_name" \
    pkglift \
    "$bundle_name"
)

tar -czf "$output_directory/$archive_name" \
  -C "$staging_directory" \
  pkglift \
  "$bundle_name"

(
  cd "$output_directory"
  shasum -a 256 "$archive_name" > "$checksum_name"
)

tar -xzf "$output_directory/$archive_name" -C "$smoke_directory"
/usr/bin/unzip -q "$output_directory/$notarization_name" -d "$notarization_smoke_directory"
cmp -s "$staging_directory/pkglift" "$smoke_directory/pkglift"
cmp -s "$staging_directory/pkglift" "$notarization_smoke_directory/pkglift"
file "$smoke_directory/pkglift" | grep -q "arm64"
xcrun vtool -show-build "$smoke_directory/pkglift" | grep -Eq 'minos 14(\.0)?'
(
  cd "$output_directory"
  shasum -a 256 -c "$checksum_name"
)
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

cp "$smoke_directory/pkglift" "$missing_bundle_directory/pkglift"
set +e
missing_bundle_output="$(
  cd /tmp
  "$missing_bundle_directory/pkglift" registry validate 2>&1
)"
missing_bundle_status=$?
set -e
if [[ $missing_bundle_status -ne 1 ]]; then
  echo "Expected missing registry bundle to exit 1, got $missing_bundle_status." >&2
  exit 1
fi
if [[ "$missing_bundle_output" != *"Could not find the bundled registry"* ]]; then
  echo "Missing registry bundle did not produce the expected typed error." >&2
  echo "$missing_bundle_output" >&2
  exit 1
fi

echo "Created and smoke-tested $output_directory/$archive_name"
echo "Created notarization input $output_directory/$notarization_name"
