#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: validate-pinned-pilot-write-root.sh PROJECT_ROOT" >&2
  exit 2
fi

project_root="$1"
if [[ ! -d "$project_root" ]]; then
  echo "Pinned pilot project root is not a directory: $project_root" >&2
  exit 2
fi

state_directory="$project_root/.pkglift"
if [[ -e "$state_directory" || -L "$state_directory" ]]; then
  echo "Pinned pilot refuses a pre-existing .pkglift path: $state_directory" >&2
  exit 1
fi
