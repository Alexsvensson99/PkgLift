#!/usr/bin/env bash
set -euo pipefail

repository="aws-samples/amazon-ivs-grid-feed-for-ios-demo"
commit="5573a57d4cb7e10f7ad86f95c548ddfbeabc6e1d"
workspace="Grid Feed.xcworkspace"
project="Grid Feed.xcodeproj"
scheme="Grid Feed"
destination="generic/platform=iOS Simulator"
configuration="Debug"

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"
: "${PKGLIFT_BIN:?PKGLIFT_BIN is required}"

baseline_root="$RUNNER_TEMP/pkglift-positive-baseline"
migration_root="$RUNNER_TEMP/pkglift-positive-migration"
report_root="$RUNNER_TEMP/pkglift-positive-e2e-report"
baseline_derived="$RUNNER_TEMP/pkglift-positive-baseline-derived"
verification_derived="$RUNNER_TEMP/pkglift-positive-verification-derived"
timeout_runner=(/usr/bin/python3 "$GITHUB_WORKSPACE/Scripts/run-with-timeout.py")

rm -rf \
  "$baseline_root" \
  "$migration_root" \
  "$report_root" \
  "$baseline_derived" \
  "$verification_derived"
mkdir -p "$report_root"

echo "POSITIVE_E2E_REPORT_DIR=$report_root" >> "$GITHUB_ENV"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

require_command git
require_command pod
require_command xcodebuild

clone_pinned() {
  local destination_root="$1"
  git init -q "$destination_root"
  git -C "$destination_root" remote add origin "https://github.com/$repository.git"
  git -C "$destination_root" fetch --depth 1 --no-tags origin "$commit"
  git -C "$destination_root" checkout -q --detach FETCH_HEAD

  local actual_commit
  actual_commit="$(git -C "$destination_root" rev-parse HEAD)"
  if [[ "$actual_commit" != "$commit" ]]; then
    echo "Fetched $actual_commit instead of pinned commit $commit" >&2
    exit 1
  fi
}

require_locked_dependency() {
  local lockfile="$1"
  local name="$2"
  local version="$3"
  if ! grep -F -- "- $name ($version)" "$lockfile" >/dev/null; then
    echo "Expected $name $version in $lockfile" >&2
    exit 1
  fi
}

validate_scheme() {
  local root="$1"
  local listing="$report_root/schemes.json"
  "${timeout_runner[@]}" \
    --seconds 180 \
    --stdout "$listing" \
    --stderr "$report_root/schemes.stderr.txt" \
    -- \
    xcodebuild \
      -workspace "$root/$workspace" \
      -list \
      -json

  SCHEME="$scheme" /usr/bin/python3 - "$listing" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    document = json.load(handle)

schemes = document.get("workspace", {}).get("schemes", [])
expected = os.environ["SCHEME"]
if expected not in schemes:
    raise SystemExit(f"Expected scheme {expected!r}; found {schemes!r}")
PY
}

validate_reviewed_auto_set() {
  local plan_path="$1"
  /usr/bin/python3 - "$plan_path" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    plan = json.load(handle)

auto_entries = sorted(
    entry.get("podName")
    for entry in plan.get("entries", [])
    if entry.get("classification") == "AUTO"
)
expected = ["SDWebImage"]
if auto_entries != expected:
    raise SystemExit(
        f"Reviewed AUTO set changed: expected {expected!r}, got {auto_entries!r}"
    )
PY
}

run_build() {
  local root="$1"
  local derived_data="$2"
  local log_path="$3"

  "${timeout_runner[@]}" \
    --seconds 1200 \
    --combined-log "$log_path" \
    -- \
    xcodebuild \
      -workspace "$root/$workspace" \
      -scheme "$scheme" \
      -configuration "$configuration" \
      -sdk iphonesimulator \
      -destination "$destination" \
      -derivedDataPath "$derived_data" \
      CODE_SIGNING_ALLOWED=NO \
      build
}

clone_pinned "$baseline_root"
clone_pinned "$migration_root"

cat > "$report_root/source.txt" <<EOF
repository=$repository
commit=$commit
license=MIT-0
workspace=$workspace
project=$project
scheme=$scheme
source_redistributed=false
upstream_write_credentials=false
EOF

{
  echo "pkglift=$($PKGLIFT_BIN version)"
  echo "git=$(git --version)"
  echo "cocoapods=$(pod --version)"
  swift --version | sed 's/^/swift=/'
  xcodebuild -version | sed 's/^/xcode=/'
} > "$report_root/environment.txt"

# Build the exact upstream dependency versions before migration in a separate
# checkout. A newer CocoaPods may normalize only its own COCOAPODS metadata;
# the two pinned direct dependency versions remain hard requirements.
"${timeout_runner[@]}" \
  --seconds 600 \
  --cwd "$baseline_root" \
  --combined-log "$report_root/baseline-pod-install.log" \
  -- \
  pod install --clean-install
require_locked_dependency "$baseline_root/Podfile.lock" "AmazonIVSPlayer" "1.40.0"
require_locked_dependency "$baseline_root/Podfile.lock" "SDWebImage" "5.18.1"
git -C "$baseline_root" diff -- Podfile.lock > "$report_root/baseline-lockfile-diff.txt"
validate_scheme "$baseline_root"
run_build "$baseline_root" "$baseline_derived" "$report_root/baseline-build.log"

# Keep generated plan and local rollback material from making the disposable
# migration checkout appear dirty. The backup is retained until job cleanup.
printf '.pkglift/plan.json\n.pkglift/backup/\n' >> "$migration_root/.git/info/exclude"

common_args=(
  --path "$migration_root"
  --workspace "$workspace"
  --project "$project"
  --no-color
)

"$PKGLIFT_BIN" analyze "${common_args[@]}" --json > "$report_root/analysis.json"
"$PKGLIFT_BIN" plan "${common_args[@]}" --json > "$report_root/plan-command.json"
cp "$migration_root/.pkglift/plan.json" "$report_root/plan.json"
"$PKGLIFT_BIN" migrate "${common_args[@]}" > "$report_root/dry-run.txt"

git -C "$migration_root" diff --exit-code --no-ext-diff
git -C "$migration_root" diff --cached --exit-code --no-ext-diff
if [[ -n "$(git -C "$migration_root" status --porcelain --untracked-files=all)" ]]; then
  echo "Dry run changed the migration checkout" >&2
  git -C "$migration_root" status --short >&2
  exit 1
fi

# Validate both individual expectations and the complete reviewed AUTO set
# before allowing any mutation.
PILOT_REPOSITORY="$repository" \
PILOT_COMMIT="$commit" \
PILOT_WORKSPACE="$workspace" \
PILOT_PROJECT="$project" \
PILOT_ISSUE="23" \
PILOT_LICENSE="MIT-0" \
PILOT_DRY_RUN_CLEAN="true" \
ruby "$GITHUB_WORKSPACE/Scripts/validate-pinned-pilot.rb" \
  positive \
  "$report_root/analysis.json" \
  "$report_root/plan.json" \
  "$report_root/dry-run.txt" \
  "$migration_root" \
  "$report_root/read-only-validation"
validate_reviewed_auto_set "$report_root/plan.json"

"$PKGLIFT_BIN" migrate "${common_args[@]}" --apply > "$report_root/apply.txt"

grep -F "pod 'AmazonIVSPlayer'" "$migration_root/Podfile" >/dev/null
if grep -F "pod 'SDWebImage'" "$migration_root/Podfile" >/dev/null; then
  echo "SDWebImage declaration remained after apply" >&2
  exit 1
fi

# Refresh only the CocoaPods dependencies that remain after PkgLift applies the
# reviewed AUTO action. The pinned lockfile should keep AmazonIVSPlayer stable.
"${timeout_runner[@]}" \
  --seconds 600 \
  --cwd "$migration_root" \
  --combined-log "$report_root/migrated-pod-install.log" \
  -- \
  pod install --clean-install

require_locked_dependency "$migration_root/Podfile.lock" "AmazonIVSPlayer" "1.40.0"
if grep -F -- '- SDWebImage (' "$migration_root/Podfile.lock" >/dev/null; then
  echo "SDWebImage remained in Podfile.lock after pod install" >&2
  exit 1
fi

"${timeout_runner[@]}" \
  --seconds 1200 \
  --stdout "$report_root/verification.json" \
  --stderr "$report_root/verification.stderr.txt" \
  -- \
  "$PKGLIFT_BIN" verify \
    "${common_args[@]}" \
    --build \
    --scheme "$scheme" \
    --configuration "$configuration" \
    --destination "$destination" \
    --sdk iphonesimulator \
    --derived-data-path "$verification_derived" \
    --json

# PkgLift and CocoaPods may update only dependency configuration. Source and
# resource changes are always unexpected in this pilot.
changed_files="$report_root/changed-files.txt"
: > "$changed_files"
while IFS= read -r -d '' path; do
  printf '%s\n' "$path" >> "$changed_files"
done < <(git -C "$migration_root" diff --name-only -z --no-ext-diff)
while IFS= read -r -d '' path; do
  printf '%s\n' "$path" >> "$changed_files"
done < <(git -C "$migration_root" ls-files --others --exclude-standard -z)
sort -u -o "$changed_files" "$changed_files"

while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  case "$path" in
    Podfile|Podfile.lock|"Grid Feed.xcodeproj/project.pbxproj"|"Grid Feed.xcworkspace/contents.xcworkspacedata"|*/Package.resolved)
      ;;
    *)
      echo "Unexpected changed file: $path" >&2
      exit 1
      ;;
  esac
done < "$changed_files"

git -C "$migration_root" diff --check

cat > "$report_root/summary.md" <<EOF
# Positive end-to-end pilot

- Repository: \`$repository\`
- Commit: \`$commit\`
- License: \`MIT-0\`
- Baseline locked dependency versions: **PASS**
- Baseline CocoaPods build: **PASS**
- Reviewed AUTO set: exactly \`SDWebImage\`
- Reviewed read-only plan validation: **PASS**
- Mutation-free dry run: **PASS**
- Applied migration: \`SDWebImage 5.18.1\` only
- Remaining CocoaPod: \`AmazonIVSPlayer 1.40.0\`
- PkgLift structural and build verification: **PASS**
- Source or resource files changed: **NO**
- Upstream write credentials used: **NO**
EOF

cat "$report_root/summary.md"
cat "$report_root/summary.md" >> "$GITHUB_STEP_SUMMARY"
