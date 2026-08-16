#!/usr/bin/env bash
set -euo pipefail

fixture="Fixtures/MixedLanguageSDWebImage"
workspace="PkgLiftMixedFixture.xcworkspace"
project="PkgLiftMixedFixture.xcodeproj"
scheme="PkgLiftMixedFixture"
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
tree_hasher=(/usr/bin/python3 "$GITHUB_WORKSPACE/Scripts/hash-pilot-tree.py")

rm -rf \
  "$baseline_root" \
  "$migration_root" \
  "$report_root" \
  "$baseline_derived" \
  "$verification_derived"
mkdir -p "$report_root"

echo "POSITIVE_E2E_REPORT_DIR=$report_root" >> "${GITHUB_ENV:-/dev/null}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

require_command ditto
require_command pod
require_command xcodebuild

copy_fixture() {
  local destination_root="$1"
  ditto "$GITHUB_WORKSPACE/$fixture" "$destination_root"
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
  local analysis_path="$1"
  local plan_path="$2"
  /usr/bin/python3 - "$analysis_path" "$plan_path" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    analysis = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    plan = json.load(handle)

auto_candidates = sorted(
    candidate.get("pod", {}).get("name")
    for candidate in analysis.get("candidates", [])
    if candidate.get("pod", {}).get("isDirect") is True
    and candidate.get("classification") == "AUTO"
)
auto_entries = sorted(
    entry.get("podName")
    for entry in plan.get("entries", [])
    if entry.get("classification") == "AUTO"
)
expected = ["SDWebImage"]
if auto_candidates != expected or auto_entries != expected:
    raise SystemExit(
        "Reviewed AUTO set changed: "
        f"expected {expected!r}, candidates={auto_candidates!r}, entries={auto_entries!r}"
    )

candidate = next(
    candidate for candidate in analysis["candidates"]
    if candidate.get("pod", {}).get("name") == "SDWebImage"
)
entry = next(entry for entry in plan["entries"] if entry.get("podName") == "SDWebImage")
expected_languages = {"swift", "objectiveC"}
candidate_languages = set(
    candidate.get("packageCandidate", {}).get("supportedConsumerLanguages", [])
)
entry_languages = set(
    entry.get("packageCandidate", {}).get("supportedConsumerLanguages", [])
)
profile = entry.get("targetSourceProfile", {})
profile_languages = set(profile.get("languages", []))
if candidate_languages != expected_languages or entry_languages != expected_languages:
    raise SystemExit("SDWebImage registry language evidence changed")
if profile.get("completeness") != "complete" or profile_languages != expected_languages:
    raise SystemExit(f"Mixed target source profile changed: {profile!r}")
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

copy_fixture "$baseline_root"
copy_fixture "$migration_root"

cat > "$report_root/source.txt" <<EOF
source=$fixture
repository_owned=true
workspace=$workspace
project=$project
scheme=$scheme
upstream_repository=none
upstream_write_credentials=false
EOF

{
  echo "pkglift=$($PKGLIFT_BIN version)"
  echo "cocoapods=$(pod --version)"
  swift --version | sed 's/^/swift=/'
  xcodebuild -version | sed 's/^/xcode=/'
} > "$report_root/environment.txt"

# Establish and build the CocoaPods baseline in one disposable copy of the
# repository-owned fixture.
"${timeout_runner[@]}" \
  --seconds 600 \
  --cwd "$baseline_root" \
  --combined-log "$report_root/baseline-pod-install.log" \
  -- \
  pod install --clean-install
require_locked_dependency "$baseline_root/Podfile.lock" "SDWebImage" "5.18.1"
cp "$baseline_root/Podfile.lock" "$report_root/baseline-lockfile.txt"
validate_scheme "$baseline_root"
run_build "$baseline_root" "$baseline_derived" "$report_root/baseline-build.log"

# Install the same locked CocoaPods baseline in the independent migration copy.
# Only this repo-owned copy may reach PkgLift's --apply path.
protected_hash_before="$(
  "${tree_hasher[@]}" "$migration_root" \
    --include App/AppDelegate.swift \
    --include App/LegacyImageLoader.m \
    --include App/Fixture.txt
)"
"${timeout_runner[@]}" \
  --seconds 600 \
  --cwd "$migration_root" \
  --combined-log "$report_root/migration-baseline-pod-install.log" \
  -- \
  pod install --clean-install
require_locked_dependency "$migration_root/Podfile.lock" "SDWebImage" "5.18.1"

common_args=(
  --path "$migration_root"
  --project "$project"
  --no-color
)

"$PKGLIFT_BIN" analyze "${common_args[@]}" --json > "$report_root/analysis.json"
"$PKGLIFT_BIN" plan "${common_args[@]}" --json > "$report_root/plan-command.json"
cp "$migration_root/.pkglift/plan.json" "$report_root/plan.json"
validate_reviewed_auto_set "$report_root/analysis.json" "$report_root/plan.json"

dry_run_tree_before="$("${tree_hasher[@]}" "$migration_root")"
"$PKGLIFT_BIN" migrate "${common_args[@]}" > "$report_root/dry-run.txt"
dry_run_tree_after="$("${tree_hasher[@]}" "$migration_root")"

if [[ "$dry_run_tree_before" != "$dry_run_tree_after" ]]; then
  echo "Dry run changed the repository-owned migration fixture" >&2
  exit 1
fi

"$PKGLIFT_BIN" migrate "${common_args[@]}" --apply > "$report_root/apply.txt"

if grep -F "pod 'SDWebImage'" "$migration_root/Podfile" >/dev/null; then
  echo "SDWebImage declaration remained after apply" >&2
  exit 1
fi

# Refresh CocoaPods after PkgLift removes the fixture's only pod declaration.
"${timeout_runner[@]}" \
  --seconds 600 \
  --cwd "$migration_root" \
  --combined-log "$report_root/migrated-pod-install.log" \
  -- \
  pod install --clean-install

if [[ -f "$migration_root/Podfile.lock" ]] && grep -F -- '- SDWebImage (' "$migration_root/Podfile.lock" >/dev/null; then
  echo "SDWebImage remained in Podfile.lock after pod install" >&2
  exit 1
fi

verification_args=(
  --path "$migration_root"
  --workspace "$workspace"
  --project "$project"
  --no-color
)

"${timeout_runner[@]}" \
  --seconds 1200 \
  --stdout "$report_root/verification.json" \
  --stderr "$report_root/verification.stderr.txt" \
  -- \
  "$PKGLIFT_BIN" verify \
    "${verification_args[@]}" \
    --build \
    --scheme "$scheme" \
    --configuration "$configuration" \
    --destination "$destination" \
    --sdk iphonesimulator \
    --derived-data-path "$verification_derived" \
    --json

# PkgLift and CocoaPods may update dependency configuration only. Source and
# resource bytes must remain identical through apply, resolution, and build.
protected_hash_after="$(
  "${tree_hasher[@]}" "$migration_root" \
    --include App/AppDelegate.swift \
    --include App/LegacyImageLoader.m \
    --include App/Fixture.txt
)"
if [[ "$protected_hash_before" != "$protected_hash_after" ]]; then
  echo "Source or resource bytes changed during the fixture migration" >&2
  exit 1
fi

cat > "$report_root/hashes.txt" <<EOF
protected_before=$protected_hash_before
protected_after=$protected_hash_after
dry_run_tree_before=$dry_run_tree_before
dry_run_tree_after=$dry_run_tree_after
EOF

cat > "$report_root/summary.md" <<EOF
# Repository-owned mixed-language end-to-end pilot

- Source: \`$fixture\`
- Source ownership: repository fixture
- Consumer languages: Swift and Objective-C in one target
- Baseline locked dependency versions: **PASS**
- Baseline CocoaPods build: **PASS**
- Reviewed AUTO set: exactly \`SDWebImage\`
- Complete target language evidence: **PASS**
- Mutation-free dry run: **PASS**
- Applied migration: \`SDWebImage 5.18.1\` only
- SwiftPM resolution and simulator build verification: **PASS**
- Source or resource files changed: **NO**
- Upstream repositories migrated: **NO**
- Upstream write credentials used: **NO**
EOF

cat "$report_root/summary.md"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$report_root/summary.md" >> "$GITHUB_STEP_SUMMARY"
fi
