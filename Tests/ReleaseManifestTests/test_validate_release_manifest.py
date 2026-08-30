from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "Scripts" / "validate-release-manifest.py"
SPEC = importlib.util.spec_from_file_location("validate_release_manifest", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Unable to load {MODULE_PATH}")
validator = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validator
SPEC.loader.exec_module(validator)


REPOSITORY = "Alexsvensson99/PkgLift"
PREPARED = "a" * 40
CURRENT = "b" * 40
MANIFEST_PATH = Path(".github/releases/v0.5.0.json")


def valid_manifest() -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "version": "0.5.0",
        "sourcePreparationCommit": PREPARED,
        "releasePullRequest": 78,
        "positivePilotWorkflowRun": 33281945442,
    }


def valid_pull_request() -> dict[str, object]:
    return {
        "number": 78,
        "state": "closed",
        "merged": True,
        "merge_commit_sha": PREPARED,
        "base": {
            "ref": "main",
            "repo": {"full_name": REPOSITORY},
        },
    }


def valid_workflow_run() -> dict[str, object]:
    return {
        "id": 33281945442,
        "path": ".github/workflows/positive-e2e.yml",
        "event": "push",
        "head_branch": "main",
        "head_sha": PREPARED,
        "status": "completed",
        "conclusion": "success",
        "repository": {"full_name": REPOSITORY},
    }


def git_reference(reference: str, sha: str) -> dict[str, object]:
    return {
        "ref": reference,
        "object": {"type": "commit", "sha": sha},
    }


class ReleaseManifestDiffTests(unittest.TestCase):
    def test_accepts_exactly_one_new_release_manifest(self) -> None:
        raw = b"A\0.github/releases/v0.5.0.json\0"
        self.assertEqual(validator.parse_single_added_manifest(raw), MANIFEST_PATH)

    def test_rejects_an_extra_file_in_the_push(self) -> None:
        raw = (
            b"A\0.github/releases/v0.5.0.json\0"
            b"M\0Sources/PkgLiftCore/Version.swift\0"
        )
        with self.assertRaisesRegex(validator.ValidationError, "exactly one file"):
            validator.parse_single_added_manifest(raw)

    def test_rejects_a_modified_existing_manifest(self) -> None:
        raw = b"M\0.github/releases/v0.5.0.json\0"
        with self.assertRaisesRegex(validator.ValidationError, "newly added"):
            validator.parse_single_added_manifest(raw)


class ReleaseManifestSchemaTests(unittest.TestCase):
    def test_accepts_the_exact_schema(self) -> None:
        context = validator.validate_manifest(valid_manifest(), MANIFEST_PATH)
        self.assertEqual(context.version, "0.5.0")
        self.assertEqual(context.source_preparation_commit, PREPARED)

    def test_rejects_unknown_or_missing_keys(self) -> None:
        document = valid_manifest()
        del document["releasePullRequest"]
        document["unreviewed"] = True
        with self.assertRaisesRegex(validator.ValidationError, "keys must match"):
            validator.validate_manifest(document, MANIFEST_PATH)

    def test_rejects_a_non_integer_schema_version(self) -> None:
        document = valid_manifest()
        document["schemaVersion"] = 1.0
        with self.assertRaisesRegex(validator.ValidationError, "integer 1"):
            validator.validate_manifest(document, MANIFEST_PATH)

    def test_rejects_boolean_or_non_positive_evidence_ids(self) -> None:
        for key, value in (
            ("releasePullRequest", True),
            ("releasePullRequest", 0),
            ("positivePilotWorkflowRun", -1),
        ):
            with self.subTest(key=key, value=value):
                document = valid_manifest()
                document[key] = value
                with self.assertRaisesRegex(validator.ValidationError, "positive integer"):
                    validator.validate_manifest(document, MANIFEST_PATH)

    def test_rejects_duplicate_json_keys(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            path.write_text('{"schemaVersion":1,"schemaVersion":1}', encoding="utf-8")
            with self.assertRaisesRegex(validator.ValidationError, "repeats JSON key"):
                validator.load_json_document(path)

    def test_rejects_a_symlink_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "target.json"
            target.write_text(json.dumps(valid_manifest()), encoding="utf-8")
            path = Path(directory) / "manifest.json"
            path.symlink_to(target)
            with self.assertRaisesRegex(validator.ValidationError, "regular file"):
                validator.load_json_document(path)


class ReleaseManifestRevisionTests(unittest.TestCase):
    def test_accepts_a_manifest_commit_immediately_after_preparation(self) -> None:
        validator.validate_revision_contract(
            PREPARED,
            CURRENT,
            PREPARED,
            is_fast_forward=True,
            current_parents=(PREPARED,),
        )

    def test_rejects_an_all_zero_before_sha(self) -> None:
        with self.assertRaisesRegex(validator.ValidationError, "concrete commit"):
            validator.validate_revision_contract(
                "0" * 40,
                CURRENT,
                PREPARED,
                is_fast_forward=True,
                current_parents=(PREPARED,),
            )

    def test_rejects_non_fast_forward_or_intervening_main_state(self) -> None:
        with self.assertRaisesRegex(validator.ValidationError, "fast-forward"):
            validator.validate_revision_contract(
                PREPARED,
                CURRENT,
                PREPARED,
                is_fast_forward=False,
                current_parents=(PREPARED,),
            )
        with self.assertRaisesRegex(validator.ValidationError, "immediately before"):
            validator.validate_revision_contract(
                "c" * 40,
                CURRENT,
                PREPARED,
                is_fast_forward=True,
                current_parents=("c" * 40,),
            )

    def test_rejects_multiple_commits_after_preparation(self) -> None:
        with self.assertRaisesRegex(validator.ValidationError, "single direct child"):
            validator.validate_revision_contract(
                PREPARED,
                CURRENT,
                PREPARED,
                is_fast_forward=True,
                current_parents=("c" * 40,),
            )


class ReleaseTagCreationTests(unittest.TestCase):
    class FakeClient:
        def __init__(self, *, main_sha: str, created_sha: str = CURRENT) -> None:
            self.main_sha = main_sha
            self.created_sha = created_sha
            self.posts: list[tuple[str, dict[str, object]]] = []

        def get_json(self, path: str) -> dict[str, object]:
            if path == "/git/ref/heads/main":
                return git_reference("refs/heads/main", self.main_sha)
            if path == "/git/ref/tags/v0.5.0":
                return git_reference("refs/tags/v0.5.0", self.created_sha)
            raise AssertionError(f"Unexpected GET {path}")

        def post_json(
            self,
            path: str,
            payload: dict[str, object],
        ) -> dict[str, object]:
            self.posts.append((path, payload))
            return git_reference("refs/tags/v0.5.0", self.created_sha)

    def test_creates_and_confirms_the_exact_tag_after_rechecking_main(self) -> None:
        client = self.FakeClient(main_sha=CURRENT)
        validator.create_validated_release_tag(
            client,
            release_tag="v0.5.0",
            target=CURRENT,
        )
        self.assertEqual(
            client.posts,
            [("/git/refs", {"ref": "refs/tags/v0.5.0", "sha": CURRENT})],
        )

    def test_rejects_a_stale_main_or_wrong_created_tag(self) -> None:
        stale_client = self.FakeClient(main_sha=PREPARED)
        with self.assertRaisesRegex(validator.ValidationError, "validated release commit"):
            validator.create_validated_release_tag(
                stale_client,
                release_tag="v0.5.0",
                target=CURRENT,
            )
        self.assertEqual(stale_client.posts, [])

        wrong_tag_client = self.FakeClient(main_sha=CURRENT, created_sha=PREPARED)
        with self.assertRaisesRegex(validator.ValidationError, "validated release commit"):
            validator.create_validated_release_tag(
                wrong_tag_client,
                release_tag="v0.5.0",
                target=CURRENT,
            )


class ReleaseManifestPullRequestTests(unittest.TestCase):
    def test_accepts_the_merged_source_preparation_pull_request(self) -> None:
        validator.validate_pull_request(
            valid_pull_request(),
            expected_number=78,
            repository=REPOSITORY,
            prepared=PREPARED,
        )

    def test_rejects_wrong_merge_repository_base_or_state(self) -> None:
        cases = []
        wrong_sha = valid_pull_request()
        wrong_sha["merge_commit_sha"] = "d" * 40
        cases.append(wrong_sha)
        wrong_repository = valid_pull_request()
        wrong_repository["base"] = {
            "ref": "main",
            "repo": {"full_name": "attacker/PkgLift"},
        }
        cases.append(wrong_repository)
        wrong_base = valid_pull_request()
        wrong_base["base"] = {
            "ref": "release",
            "repo": {"full_name": REPOSITORY},
        }
        cases.append(wrong_base)
        unmerged = valid_pull_request()
        unmerged["merged"] = False
        unmerged["state"] = "open"
        cases.append(unmerged)

        for document in cases:
            with self.subTest(document=document):
                with self.assertRaises(validator.ValidationError):
                    validator.validate_pull_request(
                        document,
                        expected_number=78,
                        repository=REPOSITORY,
                        prepared=PREPARED,
                    )


class ReleaseManifestWorkflowRunTests(unittest.TestCase):
    def test_accepts_the_successful_positive_main_pilot(self) -> None:
        validator.validate_workflow_run(
            valid_workflow_run(),
            expected_id=33281945442,
            repository=REPOSITORY,
            prepared=PREPARED,
        )

    def test_rejects_wrong_workflow_event_sha_conclusion_or_repository(self) -> None:
        mutations = (
            ("path", ".github/workflows/pilots.yml"),
            ("event", "pull_request"),
            ("head_branch", "feature"),
            ("head_sha", "e" * 40),
            ("status", "in_progress"),
            ("conclusion", "failure"),
        )
        cases = []
        for key, value in mutations:
            document = valid_workflow_run()
            document[key] = value
            cases.append(document)
        wrong_repository = valid_workflow_run()
        wrong_repository["repository"] = {"full_name": "attacker/PkgLift"}
        cases.append(wrong_repository)

        for document in cases:
            with self.subTest(document=document):
                with self.assertRaises(validator.ValidationError):
                    validator.validate_workflow_run(
                        document,
                        expected_id=33281945442,
                        repository=REPOSITORY,
                        prepared=PREPARED,
                    )


class ReleaseManifestMainIntegrationTests(unittest.TestCase):
    def run_git(self, repository: Path, *arguments: str) -> str:
        result = subprocess.run(
            ["git", *arguments],
            cwd=repository,
            check=False,
            text=True,
            capture_output=True,
        )
        if result.returncode != 0:
            raise AssertionError(
                f"git {' '.join(arguments)} failed ({result.returncode}): "
                f"{result.stderr.strip()}"
            )
        return result.stdout.strip()

    def create_repository(
        self,
        directory: Path,
        *,
        include_extra_file: bool,
        include_intervening_commit: bool = False,
    ) -> tuple[Path, str, str]:
        repository = directory / "repository"
        remote = directory / "remote.git"
        remote.mkdir()
        self.run_git(remote, "init", "--bare")
        repository.mkdir()
        self.run_git(repository, "init", "-b", "main")
        self.run_git(repository, "config", "user.name", "PkgLift Tests")
        self.run_git(
            repository,
            "config",
            "user.email",
            "25175104+Alexsvensson99@users.noreply.github.com",
        )
        self.run_git(repository, "config", "commit.gpgsign", "false")

        version_path = repository / "Sources" / "PkgLiftCore" / "Version.swift"
        version_path.parent.mkdir(parents=True)
        version_path.write_text('let pkgLiftVersion = "0.5.0"\n', encoding="utf-8")
        (repository / "CHANGELOG.md").write_text(
            "## [0.5.0] - 2026-08-30\n",
            encoding="utf-8",
        )
        self.run_git(repository, "add", "Sources/PkgLiftCore/Version.swift", "CHANGELOG.md")
        self.run_git(repository, "commit", "-m", "Prepare release")
        prepared = self.run_git(repository, "rev-parse", "HEAD")

        if include_intervening_commit:
            self.run_git(
                repository,
                "commit",
                "--allow-empty",
                "-m",
                "Intervening empty commit",
            )

        manifest_path = repository / MANIFEST_PATH
        manifest_path.parent.mkdir(parents=True)
        document = valid_manifest()
        document["sourcePreparationCommit"] = prepared
        manifest_path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        self.run_git(repository, "add", MANIFEST_PATH.as_posix())
        if include_extra_file:
            extra_path = repository / "Documentation" / "unreviewed.md"
            extra_path.parent.mkdir()
            extra_path.write_text("extra release content\n", encoding="utf-8")
            self.run_git(repository, "add", "Documentation/unreviewed.md")
        self.run_git(repository, "commit", "-m", "Add release manifest")
        current = self.run_git(repository, "rev-parse", "HEAD")
        self.run_git(repository, "remote", "add", "origin", str(remote))
        self.run_git(repository, "push", "-u", "origin", "main")
        return repository, prepared, current

    def environment(
        self,
        directory: Path,
        *,
        prepared: str,
        current: str,
    ) -> dict[str, str]:
        return {
            "BEFORE_SHA": prepared,
            "GITHUB_SHA": current,
            "GITHUB_REPOSITORY": REPOSITORY,
            "GITHUB_TOKEN": "test-token",
            "GITHUB_OUTPUT": str(directory / "output.txt"),
            "GITHUB_STEP_SUMMARY": str(directory / "summary.md"),
        }

    def test_main_accepts_a_manifest_only_commit_with_matching_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            repository, prepared, current = self.create_repository(
                directory,
                include_extra_file=False,
            )

            class FakeGitHubClient:
                def __init__(self, repository: str, token: str) -> None:
                    self.repository = repository
                    self.token = token

                def get_json(self, path: str) -> dict[str, object]:
                    if path == "/pulls/78":
                        document = valid_pull_request()
                        document["merge_commit_sha"] = prepared
                        return document
                    if path == "/actions/runs/33281945442":
                        document = valid_workflow_run()
                        document["head_sha"] = prepared
                        return document
                    raise AssertionError(f"Unexpected API path {path}")

            previous_directory = Path.cwd()
            try:
                os.chdir(repository)
                with mock.patch.object(validator, "GitHubClient", FakeGitHubClient):
                    with mock.patch.dict(
                        os.environ,
                        self.environment(directory, prepared=prepared, current=current),
                        clear=False,
                    ):
                        self.assertEqual(validator.main(), 0)
            finally:
                os.chdir(previous_directory)

            output = (directory / "output.txt").read_text(encoding="utf-8")
            self.assertIn("version=0.5.0", output)
            self.assertIn(f"target_commitish={current}", output)

    def test_main_rejects_the_original_extra_file_bypass(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            repository, prepared, current = self.create_repository(
                directory,
                include_extra_file=True,
            )
            previous_directory = Path.cwd()
            try:
                os.chdir(repository)
                with mock.patch.dict(
                    os.environ,
                    self.environment(directory, prepared=prepared, current=current),
                    clear=False,
                ):
                    with self.assertRaisesRegex(validator.ValidationError, "exactly one file"):
                        validator.main()
            finally:
                os.chdir(previous_directory)

    def test_main_rejects_multiple_commits_after_preparation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            repository, prepared, current = self.create_repository(
                directory,
                include_extra_file=False,
                include_intervening_commit=True,
            )
            previous_directory = Path.cwd()
            try:
                os.chdir(repository)
                with mock.patch.dict(
                    os.environ,
                    self.environment(directory, prepared=prepared, current=current),
                    clear=False,
                ):
                    with self.assertRaisesRegex(
                        validator.ValidationError,
                        "single direct child",
                    ):
                        validator.main()
            finally:
                os.chdir(previous_directory)


if __name__ == "__main__":
    unittest.main()
