#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <release-bin-directory> <output-directory>" >&2
  exit 2
fi

required_variables=(
  GITHUB_REPOSITORY
  GITHUB_RUN_ATTEMPT
  GITHUB_RUN_ID
  GITHUB_SHA
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Missing required environment variable: $variable" >&2
    exit 2
  fi
done

if [[ ! "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "Invalid GITHUB_REPOSITORY: $GITHUB_REPOSITORY" >&2
  exit 2
fi
if [[ ! "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Invalid GITHUB_SHA: $GITHUB_SHA" >&2
  exit 2
fi
if [[ ! "$GITHUB_RUN_ID" =~ ^[0-9]+$ || ! "$GITHUB_RUN_ATTEMPT" =~ ^[0-9]+$ ]]; then
  echo "GitHub run identifiers must be positive integers." >&2
  exit 2
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
binary_directory="$1"
output_directory="$2"
bundle_name="PkgLift_PkgLiftRegistry.bundle"
archive_name="pkglift-pilot-binary.tar.gz"

if [[ ! -d "$binary_directory" ]]; then
  echo "Release bin directory does not exist: $binary_directory" >&2
  exit 1
fi
binary_directory="$(cd "$binary_directory" && pwd -P)"
binary_path="$binary_directory/pkglift"
bundle_path="$binary_directory/$bundle_name"

if [[ ! -x "$binary_path" || -L "$binary_path" ]]; then
  echo "Expected a regular executable at $binary_path" >&2
  exit 1
fi
if [[ ! -d "$bundle_path" || -L "$bundle_path" ]]; then
  echo "Expected a regular registry bundle at $bundle_path" >&2
  exit 1
fi
bundle_symlink="$(find "$bundle_path" -type l -print -quit)"
if [[ -n "$bundle_symlink" ]]; then
  echo "Registry bundle must not contain symbolic links." >&2
  exit 1
fi

mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd -P)"
archive_path="$output_directory/$archive_name"
checksum_path="$archive_path.sha256"
if [[ -e "$archive_path" || -e "$checksum_path" ]]; then
  echo "Refusing to overwrite an existing pilot artifact in $output_directory" >&2
  exit 1
fi

temporary_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
staging_directory="$(mktemp -d "$temporary_root/pkglift-pilot-package.XXXXXX")"
smoke_parent="$(mktemp -d "$temporary_root/pkglift-pilot-smoke.XXXXXX")"
cleanup() {
  rm -rf "$staging_directory" "$smoke_parent"
}
trap cleanup EXIT

cp -p "$binary_path" "$staging_directory/pkglift"
cp -R "$bundle_path" "$staging_directory/$bundle_name"
chmod 755 "$staging_directory/pkglift"

binary_sha256="$(/usr/bin/shasum -a 256 "$staging_directory/pkglift" | awk '{print $1}')"
bundle_sha256="$(/usr/bin/python3 "$script_directory/hash-pilot-tree.py" "$staging_directory/$bundle_name")"
runner_arch="$(uname -m)"
if [[ "$runner_arch" != "arm64" ]]; then
  echo "Pinned pilot artifacts require the arm64 macos-15 runner, got $runner_arch." >&2
  exit 1
fi

cat > "$staging_directory/manifest.txt" <<EOF
schema=1
repository=$GITHUB_REPOSITORY
source_sha=$GITHUB_SHA
run_id=$GITHUB_RUN_ID
producer_run_attempt=$GITHUB_RUN_ATTEMPT
producer_job=build_pilot_toolchain
runner_arch=$runner_arch
binary_sha256=$binary_sha256
bundle_sha256=$bundle_sha256
EOF

COPYFILE_DISABLE=1 tar -czf "$archive_path" \
  -C "$staging_directory" \
  pkglift \
  "$bundle_name" \
  manifest.txt

archive_sha256="$(/usr/bin/shasum -a 256 "$archive_path" | awk '{print $1}')"
printf '%s  %s\n' "$archive_sha256" "$archive_name" > "$checksum_path"
artifact_name="pkglift-pilot-$GITHUB_SHA-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"

GITHUB_ENV='' \
PKGLIFT_EXPECTED_ARCHIVE_SHA256="$archive_sha256" \
PKGLIFT_EXPECTED_BINARY_SHA256="$binary_sha256" \
PKGLIFT_EXPECTED_PRODUCER_ATTEMPT="$GITHUB_RUN_ATTEMPT" \
PKGLIFT_EXPECTED_REPOSITORY="$GITHUB_REPOSITORY" \
PKGLIFT_EXPECTED_RUN_ID="$GITHUB_RUN_ID" \
PKGLIFT_EXPECTED_SOURCE_SHA="$GITHUB_SHA" \
  /usr/bin/python3 "$script_directory/verify-pilot-artifact.py" \
    "$archive_path" \
    "$smoke_parent/runtime"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "archive_sha256=$archive_sha256"
    echo "artifact_name=$artifact_name"
    echo "artifact_run_attempt=$GITHUB_RUN_ATTEMPT"
    echo "binary_sha256=$binary_sha256"
  } >> "$GITHUB_OUTPUT"
fi

echo "Created and verified $archive_path"
