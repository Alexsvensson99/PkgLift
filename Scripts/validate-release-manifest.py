#!/usr/bin/env python3
"""Validate a reviewed PkgLift release manifest before any release dispatch."""

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from typing import Any
import urllib.error
import urllib.request


SHA_PATTERN = re.compile(r"[0-9a-f]{40}")
VERSION_PATTERN = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?")
REPOSITORY_PATTERN = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
EXPECTED_KEYS = {
    "schemaVersion",
    "version",
    "sourcePreparationCommit",
    "releasePullRequest",
    "positivePilotWorkflowRun",
}
POSITIVE_PILOT_PATH = ".github/workflows/positive-e2e.yml"


class ValidationError(RuntimeError):
    """A fail-closed release-manifest policy violation."""


@dataclass(frozen=True)
class ManifestContext:
    version: str
    release_tag: str
    source_preparation_commit: str
    release_pull_request: int
    positive_pilot_workflow_run: int


def require_sha(value: object, label: str, *, allow_zero: bool = False) -> str:
    if not isinstance(value, str) or SHA_PATTERN.fullmatch(value) is None:
        raise ValidationError(f"{label} must be a full lowercase commit SHA")
    if not allow_zero and set(value) == {"0"}:
        raise ValidationError(f"{label} must identify a concrete commit")
    return value


def require_positive_integer(value: object, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValidationError(f"{label} must be a positive integer")
    return value


def load_json_document(path: Path) -> dict[str, Any]:
    def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValidationError(f"Release manifest repeats JSON key {key!r}")
            result[key] = value
        return result

    try:
        file_status = path.lstat()
        if not stat.S_ISREG(file_status.st_mode):
            raise ValidationError("Release manifest must be a regular file")
        document = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_keys,
        )
    except OSError as error:
        raise ValidationError(f"Unable to read release manifest {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise ValidationError(f"Release manifest is invalid JSON: {error}") from error
    if not isinstance(document, dict):
        raise ValidationError("Release manifest must be a JSON object")
    return document


def validate_manifest(document: dict[str, Any], path: Path) -> ManifestContext:
    actual_keys = set(document)
    if actual_keys != EXPECTED_KEYS:
        missing = sorted(EXPECTED_KEYS - actual_keys)
        extra = sorted(actual_keys - EXPECTED_KEYS)
        raise ValidationError(
            f"Release manifest keys must match the schema; missing={missing}, extra={extra}"
        )

    schema_version = document["schemaVersion"]
    if (
        isinstance(schema_version, bool)
        or not isinstance(schema_version, int)
        or schema_version != 1
    ):
        raise ValidationError("Release manifest schemaVersion must be integer 1")

    version = document["version"]
    if not isinstance(version, str) or VERSION_PATTERN.fullmatch(version) is None:
        raise ValidationError("Release manifest version is invalid")
    release_tag = f"v{version}"
    expected_path = Path(f".github/releases/{release_tag}.json")
    if path != expected_path:
        raise ValidationError(f"Manifest path must be {expected_path}, not {path}")

    prepared = require_sha(
        document["sourcePreparationCommit"],
        "sourcePreparationCommit",
    )
    release_pull_request = require_positive_integer(
        document["releasePullRequest"],
        "releasePullRequest",
    )
    positive_pilot_workflow_run = require_positive_integer(
        document["positivePilotWorkflowRun"],
        "positivePilotWorkflowRun",
    )
    return ManifestContext(
        version=version,
        release_tag=release_tag,
        source_preparation_commit=prepared,
        release_pull_request=release_pull_request,
        positive_pilot_workflow_run=positive_pilot_workflow_run,
    )


def parse_single_added_manifest(raw_diff: bytes) -> Path:
    fields = raw_diff.split(b"\0")
    if fields and fields[-1] == b"":
        fields.pop()
    if len(fields) != 2:
        raise ValidationError(
            "Release manifest push must change exactly one file in the entire repository"
        )
    try:
        status = fields[0].decode("ascii")
        path = Path(fields[1].decode("utf-8"))
    except UnicodeDecodeError as error:
        raise ValidationError("Release manifest diff contains a non-UTF-8 path") from error
    if status != "A":
        raise ValidationError(
            f"Release manifest must be newly added, but Git reported status {status!r}"
        )
    if not re.fullmatch(r"\.github/releases/v[^/]+\.json", path.as_posix()):
        raise ValidationError(f"Only a versioned release manifest may change, not {path}")
    return path


def validate_revision_contract(
    before: str,
    current: str,
    prepared: str,
    *,
    is_fast_forward: bool,
    current_parents: tuple[str, ...],
) -> None:
    require_sha(before, "Previous main SHA")
    require_sha(current, "Current workflow SHA")
    require_sha(prepared, "sourcePreparationCommit")
    if not is_fast_forward:
        raise ValidationError("Release manifest push must be a fast-forward update of main")
    if prepared != before:
        raise ValidationError(
            "sourcePreparationCommit must be the main commit immediately before the "
            "manifest-only commit"
        )
    if current_parents != (before,):
        raise ValidationError(
            "Release manifest commit must be the single direct child of "
            "sourcePreparationCommit"
        )


def validate_pull_request(
    document: dict[str, Any],
    *,
    expected_number: int,
    repository: str,
    prepared: str,
) -> None:
    if document.get("number") != expected_number:
        raise ValidationError("GitHub returned a different release pull request")
    if document.get("merged") is not True or document.get("state") != "closed":
        raise ValidationError("Release pull request must be merged and closed")
    base = document.get("base")
    base_repository = base.get("repo") if isinstance(base, dict) else None
    full_name = (
        base_repository.get("full_name")
        if isinstance(base_repository, dict)
        else None
    )
    if not isinstance(full_name, str) or full_name.casefold() != repository.casefold():
        raise ValidationError("Release pull request targets a different repository")
    if not isinstance(base, dict) or base.get("ref") != "main":
        raise ValidationError("Release pull request must target main")
    if document.get("merge_commit_sha") != prepared:
        raise ValidationError(
            "Release pull request merge commit does not match sourcePreparationCommit"
        )


def validate_workflow_run(
    document: dict[str, Any],
    *,
    expected_id: int,
    repository: str,
    prepared: str,
) -> None:
    if document.get("id") != expected_id:
        raise ValidationError("GitHub returned a different positive pilot workflow run")
    run_repository = document.get("repository")
    full_name = (
        run_repository.get("full_name")
        if isinstance(run_repository, dict)
        else None
    )
    if not isinstance(full_name, str) or full_name.casefold() != repository.casefold():
        raise ValidationError("Positive pilot workflow run belongs to another repository")
    if document.get("path") != POSITIVE_PILOT_PATH:
        raise ValidationError(
            f"Positive pilot evidence must come from {POSITIVE_PILOT_PATH}"
        )
    if document.get("event") != "push" or document.get("head_branch") != "main":
        raise ValidationError("Positive pilot workflow run must be a main push run")
    if document.get("head_sha") != prepared:
        raise ValidationError(
            "Positive pilot workflow run does not match sourcePreparationCommit"
        )
    if document.get("status") != "completed" or document.get("conclusion") != "success":
        raise ValidationError("Positive pilot workflow run must be completed successfully")


class GitHubClient:
    def __init__(self, repository: str, token: str) -> None:
        if REPOSITORY_PATTERN.fullmatch(repository) is None:
            raise ValidationError("GITHUB_REPOSITORY is invalid")
        if not token:
            raise ValidationError("GITHUB_TOKEN is required for release evidence checks")
        self.api_root = f"https://api.github.com/repos/{repository}"
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "PkgLift-release-manifest",
        }

    def request_json(
        self,
        path: str,
        *,
        method: str = "GET",
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        data = None
        headers = dict(self.headers)
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{self.api_root}{path}",
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                document = json.load(response)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise ValidationError(f"GitHub API {error.code}: {detail}") from error
        except (urllib.error.URLError, TimeoutError) as error:
            raise ValidationError(f"GitHub API request failed: {error}") from error
        if not isinstance(document, dict):
            raise ValidationError("GitHub API returned an unexpected document")
        return document

    def get_json(self, path: str) -> dict[str, Any]:
        return self.request_json(path)

    def post_json(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request_json(path, method="POST", payload=payload)


def validate_git_reference(
    document: dict[str, Any],
    *,
    expected_ref: str,
    target: str,
    label: str,
) -> None:
    reference_object = document.get("object")
    if document.get("ref") != expected_ref:
        raise ValidationError(f"{label} returned an unexpected Git reference")
    if not isinstance(reference_object, dict):
        raise ValidationError(f"{label} returned no Git object")
    if reference_object.get("type") != "commit" or reference_object.get("sha") != target:
        raise ValidationError(f"{label} does not point to the validated release commit")


def create_validated_release_tag(
    client: GitHubClient,
    *,
    release_tag: str,
    target: str,
) -> None:
    tag_ref = f"refs/tags/{release_tag}"
    main_reference = client.get_json("/git/ref/heads/main")
    validate_git_reference(
        main_reference,
        expected_ref="refs/heads/main",
        target=target,
        label="Current main reference",
    )

    created_reference = client.post_json(
        "/git/refs",
        {"ref": tag_ref, "sha": target},
    )
    validate_git_reference(
        created_reference,
        expected_ref=tag_ref,
        target=target,
        label="Created release tag",
    )
    confirmed_reference = client.get_json(f"/git/ref/tags/{release_tag}")
    validate_git_reference(
        confirmed_reference,
        expected_ref=tag_ref,
        target=target,
        label="Confirmed release tag",
    )


def run_git(*arguments: str, check: bool = True, text: bool = True) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            ["git", *arguments],
            check=check,
            text=text,
            capture_output=True,
        )
    except subprocess.CalledProcessError as error:
        stderr = error.stderr.strip() if isinstance(error.stderr, str) else ""
        detail = stderr or f"exit {error.returncode}"
        raise ValidationError(f"git {' '.join(arguments)} failed: {detail}") from error


def require_commit(sha: str, label: str) -> None:
    result = run_git("cat-file", "-e", f"{sha}^{{commit}}", check=False)
    if result.returncode != 0:
        raise ValidationError(f"{label} {sha} is not available as a commit")


def git_is_ancestor(ancestor: str, descendant: str) -> bool:
    result = run_git("merge-base", "--is-ancestor", ancestor, descendant, check=False)
    if result.returncode not in {0, 1}:
        raise ValidationError("Unable to verify the release manifest commit ancestry")
    return result.returncode == 0


def required_environment(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise ValidationError(f"{name} is required")
    return value


def validate_source_contract(context: ManifestContext) -> None:
    version_source = Path("Sources/PkgLiftCore/Version.swift").read_text(encoding="utf-8")
    match = re.search(r'pkgLiftVersion\s*=\s*"([^"]+)"', version_source)
    if match is None or match.group(1) != context.version:
        raise ValidationError(
            f"Manifest version {context.version} does not match the source version"
        )
    changelog = Path("CHANGELOG.md").read_text(encoding="utf-8")
    if f"## [{context.version}] -" not in changelog:
        raise ValidationError(
            f"CHANGELOG.md has no dated {context.version} release heading"
        )


def ensure_tag_is_available(release_tag: str) -> None:
    result = run_git(
        "ls-remote",
        "--exit-code",
        "--tags",
        "origin",
        f"refs/tags/{release_tag}",
        check=False,
    )
    if result.returncode == 0:
        raise ValidationError(
            f"Tag {release_tag} already exists; refusing duplicate publication"
        )
    if result.returncode != 2:
        raise ValidationError("Unable to verify release-tag availability")


def main() -> int:
    before = require_sha(required_environment("BEFORE_SHA"), "Previous main SHA")
    current = require_sha(required_environment("GITHUB_SHA"), "Current workflow SHA")
    repository = required_environment("GITHUB_REPOSITORY")
    output_path = Path(required_environment("GITHUB_OUTPUT"))
    summary_path = Path(required_environment("GITHUB_STEP_SUMMARY"))

    require_commit(before, "Previous main commit")
    require_commit(current, "Current workflow commit")
    is_fast_forward = git_is_ancestor(before, current)
    current_parents = tuple(
        run_git("show", "-s", "--format=%P", current).stdout.strip().split()
    )

    main_ref = run_git("ls-remote", "origin", "refs/heads/main").stdout.strip().split()
    if not main_ref or main_ref[0] != current:
        raise ValidationError(
            f"Release manifest must run at current main head {current}; got {main_ref[:1]}"
        )

    diff = run_git(
        "diff",
        "--name-status",
        "--no-renames",
        "-z",
        before,
        current,
        "--",
        text=False,
    ).stdout
    manifest_path = parse_single_added_manifest(diff)
    document = load_json_document(manifest_path)
    context = validate_manifest(document, manifest_path)
    validate_revision_contract(
        before,
        current,
        context.source_preparation_commit,
        is_fast_forward=is_fast_forward,
        current_parents=current_parents,
    )
    validate_source_contract(context)
    ensure_tag_is_available(context.release_tag)

    client = GitHubClient(repository, required_environment("GITHUB_TOKEN"))
    pull_request = client.get_json(f"/pulls/{context.release_pull_request}")
    validate_pull_request(
        pull_request,
        expected_number=context.release_pull_request,
        repository=repository,
        prepared=context.source_preparation_commit,
    )
    workflow_run = client.get_json(
        f"/actions/runs/{context.positive_pilot_workflow_run}"
    )
    validate_workflow_run(
        workflow_run,
        expected_id=context.positive_pilot_workflow_run,
        repository=repository,
        prepared=context.source_preparation_commit,
    )

    with output_path.open("a", encoding="utf-8") as output:
        output.write(f"version={context.version}\n")
        output.write(f"release_tag={context.release_tag}\n")
        output.write(f"target_commitish={current}\n")

    with summary_path.open("a", encoding="utf-8") as summary:
        summary.write("### Reviewed release manifest\n\n")
        summary.write(f"- Manifest: `{manifest_path}`\n")
        summary.write(f"- Version: `{context.version}`\n")
        summary.write(f"- Tag to create: `{context.release_tag}`\n")
        summary.write(f"- Release target: `{current}`\n")
        summary.write(
            f"- Source preparation commit: `{context.source_preparation_commit}`\n"
        )
        summary.write(
            f"- Merged release PR: `{context.release_pull_request}`\n"
        )
        summary.write(
            "- Successful positive pilot run: "
            f"`{context.positive_pilot_workflow_run}`\n"
        )
    return 0


def create_tag_main() -> int:
    repository = required_environment("GITHUB_REPOSITORY")
    release_tag = required_environment("RELEASE_TAG")
    target = require_sha(
        required_environment("TARGET_COMMITISH"),
        "Validated release target",
    )
    if not release_tag.startswith("v") or VERSION_PATTERN.fullmatch(release_tag[1:]) is None:
        raise ValidationError("RELEASE_TAG must be a versioned vX.Y.Z tag")

    client = GitHubClient(repository, required_environment("GITHUB_TOKEN"))
    create_validated_release_tag(
        client,
        release_tag=release_tag,
        target=target,
    )
    print(f"Created and verified {release_tag} at {target}")
    return 0


if __name__ == "__main__":
    try:
        if sys.argv[1:] == []:
            raise SystemExit(main())
        if sys.argv[1:] == ["create-tag"]:
            raise SystemExit(create_tag_main())
        raise ValidationError("Usage: validate-release-manifest.py [create-tag]")
    except ValidationError as error:
        print(f"Release manifest validation failed: {error}", file=sys.stderr)
        raise SystemExit(1) from None
