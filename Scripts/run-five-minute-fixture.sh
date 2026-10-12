#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: Scripts/run-five-minute-fixture.sh [--pkglift PATH] [--keep]

Run PkgLift's registry validation, analysis, plan, and dry run against a fresh
copy of the repository-owned PartialSwift fixture. The script never runs
--apply, CocoaPods, xcodebuild, or a simulator.

Options:
  --pkglift PATH  Use a specific PkgLift executable instead of PATH lookup.
  --keep          Keep the disposable fixture copy after a successful run.
  -h, --help      Show this help.
EOF
}

fail() {
  printf 'Five-minute fixture failed: %s\n' "$1" >&2
  exit 1
}

pkglift_argument=""
keep_fixture=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pkglift)
      [[ $# -ge 2 ]] || fail "--pkglift requires an executable path"
      pkglift_argument="$2"
      shift 2
      ;;
    --keep)
      keep_fixture=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
done

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd -- "$script_directory/.." && pwd -P)"
fixture_relative="Fixtures/PartialSwift"
fixture_source="$repository_root/$fixture_relative"
project_name="SwiftKeychainAccess.xcodeproj"

[[ -d "$fixture_source" ]] || fail "fixture not found: $fixture_relative"

if [[ -n "$pkglift_argument" ]]; then
  [[ -x "$pkglift_argument" ]] || fail "PkgLift executable is not executable: $pkglift_argument"
  pkglift_directory="$(cd -- "$(dirname -- "$pkglift_argument")" && pwd -P)"
  pkglift_binary="$pkglift_directory/$(basename -- "$pkglift_argument")"
else
  pkglift_binary="$(command -v pkglift || true)"
  [[ -n "$pkglift_binary" ]] || fail "pkglift was not found in PATH; install it or pass --pkglift PATH"
fi

git -C "$repository_root" diff --quiet -- "$fixture_relative" || \
  fail "$fixture_relative has unstaged changes"
git -C "$repository_root" diff --cached --quiet -- "$fixture_relative" || \
  fail "$fixture_relative has staged changes"
[[ -z "$(git -C "$repository_root" ls-files --others -- "$fixture_relative")" ]] || \
  fail "$fixture_relative has untracked or ignored files"
[[ -z "$(find "$fixture_source" -type l -print -quit)" ]] || \
  fail "$fixture_relative must not contain symbolic links"

temporary_root="${TMPDIR:-/tmp}"
temporary_root="${temporary_root%/}"
[[ -d "$temporary_root" && -w "$temporary_root" ]] || \
  fail "temporary directory is unavailable: $temporary_root"

fixture_copy="$(mktemp -d "$temporary_root/pkglift-five-minute.XXXXXX")"

cleanup() {
  exit_code=$?
  if [[ -d "$fixture_copy" ]]; then
    if [[ $exit_code -eq 0 && $keep_fixture -eq 0 ]]; then
      rm -rf -- "$fixture_copy"
    else
      printf 'Disposable fixture kept at: %s\n' "$fixture_copy" >&2
    fi
  fi
}
trap cleanup EXIT

cp -R "$fixture_source/." "$fixture_copy/"
git -C "$fixture_copy" -c init.templateDir= init -q
mkdir -p "$fixture_copy/.git/empty-hooks"
git -C "$fixture_copy" add -f -- .
git -C "$fixture_copy" \
  -c user.name='PkgLift Fixture Runner' \
  -c user.email='pkglift-fixture@example.invalid' \
  -c commit.gpgSign=false \
  -c core.hooksPath="$fixture_copy/.git/empty-hooks" \
  commit -qm 'Fixture baseline'

git -C "$fixture_copy" diff --quiet || fail "disposable fixture did not start with a clean working tree"
git -C "$fixture_copy" diff --cached --quiet || fail "disposable fixture did not start with a clean index"
[[ -z "$(git -C "$fixture_copy" ls-files --others -- .)" ]] || \
  fail "disposable fixture did not start clean"

printf 'Using PkgLift executable: %s\n' "$pkglift_binary"
printf 'Disposable repository-owned fixture: %s\n\n' "$fixture_copy"

(
  cd "$fixture_copy"
  "$pkglift_binary" version
  "$pkglift_binary" registry validate --path "$fixture_copy" --no-color
)

analysis_output="$(
  cd "$fixture_copy"
  "$pkglift_binary" analyze \
    --path "$fixture_copy" \
    --project "$project_name" \
    --no-color
)"
printf '%s\n' "$analysis_output"
[[ "$analysis_output" == *"Direct dependencies: 2"* ]] || \
  fail "analysis did not report the expected direct-dependency count"
[[ "$analysis_output" == *"AUTO: KeychainAccess"* ]] || \
  fail "analysis did not classify KeychainAccess as AUTO"
[[ "$analysis_output" == *"BLOCKED: SDWebImage"* ]] || \
  fail "analysis did not keep SDWebImage BLOCKED"

plan_output="$(
  cd "$fixture_copy"
  "$pkglift_binary" plan \
    --path "$fixture_copy" \
    --project "$project_name" \
    --no-color
)"
printf '%s\n' "$plan_output"
for expected_count in "AUTO: 1" "REVIEW: 0" "BLOCKED: 1" "UNKNOWN: 0"; do
  [[ "$plan_output" == *"$expected_count"* ]] || \
    fail "plan did not report expected count: $expected_count"
done

plan_path="$fixture_copy/.pkglift/plan.json"
[[ -f "$plan_path" && ! -L "$plan_path" && -s "$plan_path" ]] || \
  fail "plan.json was not created as a non-empty regular file"
git -C "$fixture_copy" diff --quiet || fail "plan generation changed tracked fixture content"
git -C "$fixture_copy" diff --cached --quiet || fail "plan generation changed the fixture index"
[[ "$(git -C "$fixture_copy" ls-files --others -- .)" == ".pkglift/plan.json" ]] || \
  fail "plan generation did not leave exactly one expected untracked plan file"
plan_hash_before="$(shasum -a 256 "$plan_path")"
plan_hash_before="${plan_hash_before%% *}"

dry_run_output="$(
  cd "$fixture_copy"
  "$pkglift_binary" migrate \
    --path "$fixture_copy" \
    --project "$project_name" \
    --no-color
)"
printf '%s\n' "$dry_run_output"
[[ "$dry_run_output" == *"Dry run mode."* ]] || \
  fail "migrate did not report dry-run mode"
[[ "$dry_run_output" == *"KeychainAccess"* ]] || \
  fail "dry run did not contain the reviewed KeychainAccess migration"

[[ -f "$plan_path" && ! -L "$plan_path" && -s "$plan_path" ]] || \
  fail "dry run replaced plan.json with an invalid file type"
plan_hash_after="$(shasum -a 256 "$plan_path")"
plan_hash_after="${plan_hash_after%% *}"
[[ "$plan_hash_before" == "$plan_hash_after" ]] || \
  fail "dry run changed the reviewed plan"

unexpected_artifact="$(find "$fixture_copy/.pkglift" -mindepth 1 ! -path "$plan_path" -print -quit)"
[[ -z "$unexpected_artifact" ]] || \
  fail "dry run created an unexpected .pkglift artifact: $unexpected_artifact"

git -C "$fixture_copy" diff --exit-code
git -C "$fixture_copy" diff --cached --exit-code
[[ "$(git -C "$fixture_copy" ls-files --others -- .)" == ".pkglift/plan.json" ]] || \
  fail "dry run created untracked content beyond the expected plan"

git -C "$repository_root" diff --quiet -- "$fixture_relative" || \
  fail "source fixture changed during the run"
git -C "$repository_root" diff --cached --quiet -- "$fixture_relative" || \
  fail "source fixture staging changed during the run"
[[ -z "$(git -C "$repository_root" ls-files --others -- "$fixture_relative")" ]] || \
  fail "source fixture gained untracked or ignored files during the run"
[[ -z "$(find "$fixture_source" -type l -print -quit)" ]] || \
  fail "source fixture gained a symbolic link during the run"

printf '\nFive-minute fixture completed safely.\n'
printf 'Result: AUTO 1 / REVIEW 0 / BLOCKED 1 / UNKNOWN 0\n'
printf 'The reviewed plan stayed unchanged, only that plan is untracked, and no --apply was run.\n'
