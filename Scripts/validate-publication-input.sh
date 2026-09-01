#!/usr/bin/env bash

set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [release-directory]" >&2
  exit 2
fi

release_directory="${1:-release}"
expected_files=(
  "$release_directory/pkglift-macos-arm64.tar.gz"
  "$release_directory/pkglift-macos-arm64.tar.gz.sha256"
)

if [[ ! -d "$release_directory" || -L "$release_directory" ]]; then
  echo "Validated publication input must be a real directory: $release_directory" >&2
  exit 1
fi

shopt -s nullglob dotglob
publication_entries=("$release_directory"/*)
if [[ ${#publication_entries[@]} -ne ${#expected_files[@]} ]]; then
  echo "Validated publication input must contain exactly two entries." >&2
  printf 'Found: %s\n' "${publication_entries[@]:-<none>}" >&2
  exit 1
fi

for expected_file in "${expected_files[@]}"; do
  if [[ ! -f "$expected_file" || -L "$expected_file" || ! -s "$expected_file" ]]; then
    echo "Validated publication input is missing a non-empty regular file: $expected_file" >&2
    exit 1
  fi
done
