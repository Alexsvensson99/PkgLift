#!/usr/bin/env bash
set -euo pipefail

required_variables=(
  GITHUB_WORKSPACE
  PKGLIFT_BIN
  PILOT_CASE
  PILOT_REPOSITORY
  PILOT_COMMIT
  PILOT_ROOT
  PILOT_WORKSPACE
  PILOT_PROJECT
  PILOT_ISSUE
  PILOT_LICENSE
  RUNNER_TEMP
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Missing required environment variable: $variable" >&2
    exit 2
  fi
done

case "$PILOT_CASE" in
  positive|mixed|negative|tinode|xcodebenchmark|hammerspoon|acknowlist|fastlane|firebaseui|firebaseauth) ;;
  *)
    echo "Unsupported pilot case: $PILOT_CASE" >&2
    exit 2
    ;;
esac

case "$PILOT_ROOT" in
  .)
    ;;
  ""|/*|..|../*|*/..|*/../*)
    echo "PILOT_ROOT must be a contained relative directory: $PILOT_ROOT" >&2
    exit 2
    ;;
esac

source_root="$RUNNER_TEMP/pkglift-pilot-source/$PILOT_CASE"
raw_root="$RUNNER_TEMP/pkglift-pilot-raw/$PILOT_CASE"
report_root="$RUNNER_TEMP/pkglift-pilot-report/$PILOT_CASE"

if [[ "$PILOT_WORKSPACE" == "-" ]]; then
  workspace_report="none (explicit project selection)"
else
  workspace_report="$PILOT_WORKSPACE"
fi

pkglift_binary_sha256="$(/usr/bin/shasum -a 256 "$PKGLIFT_BIN" | awk '{print $1}')"
if [[ -n "${PKGLIFT_BINARY_SHA256:-}" && "$pkglift_binary_sha256" != "$PKGLIFT_BINARY_SHA256" ]]; then
  echo "PkgLift binary changed after artifact verification." >&2
  exit 1
fi

rm -rf "$source_root" "$raw_root" "$report_root"
mkdir -p "$source_root" "$raw_root" "$report_root"

echo "PILOT_REPORT_DIR=$report_root" >> "${GITHUB_ENV:-/dev/null}"

cat > "$report_root/source.txt" <<EOF
repository=$PILOT_REPOSITORY
commit=$PILOT_COMMIT
root=$PILOT_ROOT
workspace=$workspace_report
project=$PILOT_PROJECT
tracking_issue=$PILOT_ISSUE
upstream_license_metadata=$PILOT_LICENSE
source_redistributed=false
EOF

{
  echo "pkglift=$($PKGLIFT_BIN version)"
  echo "pkglift_sha256=$pkglift_binary_sha256"
  echo "pkglift_source_sha=${PKGLIFT_ARTIFACT_SOURCE_SHA:-local-build}"
  echo "pkglift_artifact_run_id=${PKGLIFT_ARTIFACT_RUN_ID:-local-build}"
  echo "pkglift_artifact_run_attempt=${PKGLIFT_ARTIFACT_RUN_ATTEMPT:-local-build}"
  echo "git=$(git --version)"
  swift --version | sed 's/^/swift=/'
  xcodebuild -version | sed 's/^/xcode=/'
  if command -v pod >/dev/null 2>&1; then
    echo "cocoapods=$(pod --version)"
  else
    echo "cocoapods=not-installed"
  fi
} > "$report_root/environment.txt"

git init -q "$source_root"
git -C "$source_root" remote add origin "https://github.com/$PILOT_REPOSITORY.git"
git -C "$source_root" fetch --depth 1 --filter=blob:none --no-tags origin "$PILOT_COMMIT"
if [[ "$PILOT_ROOT" != "." ]]; then
  git -C "$source_root" sparse-checkout init --cone
  git -C "$source_root" sparse-checkout set -- "$PILOT_ROOT"
fi
git -C "$source_root" checkout -q --detach FETCH_HEAD

actual_commit="$(git -C "$source_root" rev-parse HEAD)"
if [[ "$actual_commit" != "$PILOT_COMMIT" ]]; then
  echo "Fetched $actual_commit instead of pinned commit $PILOT_COMMIT" >&2
  exit 1
fi

source_root_physical="$(cd "$source_root" && pwd -P)"
if [[ "$PILOT_ROOT" == "." ]]; then
  project_root_candidate="$source_root"
else
  project_root_candidate="$source_root/$PILOT_ROOT"
fi

if [[ ! -d "$project_root_candidate" ]]; then
  echo "Pinned pilot root does not exist: $PILOT_ROOT" >&2
  exit 1
fi

project_root="$(cd "$project_root_candidate" && pwd -P)"
case "$project_root" in
  "$source_root_physical")
    plan_exclude=".pkglift/plan.json"
    ;;
  "$source_root_physical"/*)
    project_relative="${project_root#"$source_root_physical"/}"
    plan_exclude="$project_relative/.pkglift/plan.json"
    ;;
  *)
    echo "Pinned pilot root resolves outside the disposable checkout: $PILOT_ROOT" >&2
    exit 1
    ;;
esac
source_root="$source_root_physical"

bash "$GITHUB_WORKSPACE/Scripts/validate-pinned-pilot-write-root.sh" "$project_root"

printf '%s\n' "$plan_exclude" >> "$source_root/.git/info/exclude"

initial_status="$(git -C "$source_root" status --porcelain --untracked-files=all)"
if [[ -n "$initial_status" ]]; then
  echo "Pinned checkout was not clean before analysis:" >&2
  printf '%s\n' "$initial_status" >&2
  exit 1
fi

common_args=(
  --path "$project_root"
  --project "$PILOT_PROJECT"
  --no-color
)
if [[ "$PILOT_WORKSPACE" != "-" ]]; then
  common_args+=(--workspace "$PILOT_WORKSPACE")
fi

"$PKGLIFT_BIN" analyze "${common_args[@]}" --json > "$raw_root/analysis.json"
"$PKGLIFT_BIN" analyze "${common_args[@]}" --portable-json > "$raw_root/analysis-portable.json"
"$PKGLIFT_BIN" plan "${common_args[@]}" --portable-json > "$raw_root/plan-portable.json"
cp "$project_root/.pkglift/plan.json" "$raw_root/plan.json"
"$PKGLIFT_BIN" migrate "${common_args[@]}" > "$raw_root/dry-run.txt"

git -C "$source_root" diff --exit-code --no-ext-diff
git -C "$source_root" diff --cached --exit-code --no-ext-diff
final_status="$(git -C "$source_root" status --porcelain --untracked-files=all)"
if [[ -n "$final_status" ]]; then
  echo "Pilot commands changed visible worktree state:" >&2
  printf '%s\n' "$final_status" >&2
  exit 1
fi

export PILOT_DRY_RUN_CLEAN=true

set +e
ruby "$GITHUB_WORKSPACE/Scripts/validate-pinned-pilot.rb" \
  "$PILOT_CASE" \
  "$raw_root/analysis.json" \
  "$raw_root/plan.json" \
  "$raw_root/dry-run.txt" \
  "$project_root" \
  "$report_root" \
  "$raw_root/analysis-portable.json" \
  "$raw_root/plan-portable.json"
validation_status=$?
set -e

cat "$report_root/summary.md"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$report_root/summary.md" >> "$GITHUB_STEP_SUMMARY"
fi

exit "$validation_status"
