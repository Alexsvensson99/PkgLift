"""Verify that release acceptance stays bound to the exact signed candidate."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = ROOT / ".github/workflows/release.yml"


def load_workflow() -> dict[str, object]:
    result = subprocess.run(
        [
            "ruby",
            "-ryaml",
            "-rjson",
            "-e",
            "puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), aliases: true))",
            str(WORKFLOW_PATH),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    workflow = json.loads(result.stdout)
    if "true" in workflow:
        workflow["on"] = workflow.pop("true")
    return workflow


class ReleaseWorkflowAcceptanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = load_workflow()
        cls.package = cls.workflow["jobs"]["package"]
        cls.package_steps = cls.package["steps"]
        cls.acceptance = cls.workflow["jobs"]["acceptance"]
        cls.acceptance_steps = cls.acceptance["steps"]
        cls.runtime = cls.workflow["jobs"]["runtime-macos14"]

    def step(self, name: str, steps: list[dict[str, object]] | None = None) -> dict[str, object]:
        matches = [step for step in (steps or self.package_steps) if step.get("name") == name]
        self.assertEqual(len(matches), 1, f"Expected exactly one {name!r} step")
        return matches[0]

    def step_index(self, name: str, steps: list[dict[str, object]] | None = None) -> int:
        selected = steps or self.package_steps
        return selected.index(self.step(name, selected))

    def test_package_publishes_only_after_signing_notarization_and_smoke_verification(self) -> None:
        ordered_steps = (
            "Notarize Distribution",
            "Verify Quarantined CLI",
            "Upload Validated Distribution",
        )
        indexes = [self.step_index(name) for name in ordered_steps]
        self.assertEqual(indexes, sorted(indexes))
        for name in ordered_steps:
            self.assertNotIn("continue-on-error", self.step(name))

    def test_consumer_acceptance_is_a_separate_least_privilege_job(self) -> None:
        self.assertEqual(self.acceptance["needs"], "package")
        self.assertEqual(self.acceptance["timeout-minutes"], 90)
        self.assertNotIn("environment", self.acceptance)
        self.assertEqual(self.acceptance["permissions"], {"actions": "read", "contents": "read"})
        serialized = json.dumps(self.acceptance)
        self.assertNotIn("secrets.", serialized)
        self.assertNotIn("DEVELOPER_ID", serialized)
        self.assertNotIn("NOTARY_", serialized)
        package_serialized = json.dumps(self.package)
        for consumer_runner in (
            "run-positive-e2e-pilot.sh",
            "run-partial-migration-pilot.py",
            "run-real-project-refusal.py",
        ):
            self.assertNotIn(consumer_runner, package_serialized)
        ordered_steps = (
            "Download Exact Signed Candidate",
            "Stage Exact Signed Candidate for Workflow Acceptance",
            "Accept Signed Candidate Full Migration",
            "Accept Signed Candidate Partial Migration",
            "Accept Signed Candidate Conservative Refusal",
            "Collect Signed Candidate Acceptance Evidence",
            "Upload Signed Candidate Acceptance Evidence",
        )
        indexes = [self.step_index(name, self.acceptance_steps) for name in ordered_steps]
        self.assertEqual(indexes, sorted(indexes))
        for name in ordered_steps:
            self.assertNotIn("continue-on-error", self.step(name, self.acceptance_steps))

    def test_exact_signed_binary_identity_is_bound_before_all_three_flows(self) -> None:
        signing = self.step("Sign Release Binary")["run"]
        staging = self.step(
            "Stage Exact Signed Candidate for Workflow Acceptance", self.acceptance_steps
        )["run"]
        self.assertIn("PKGLIFT_SIGNED_BINARY_SHA256", signing)
        self.assertIn(
            '[[ "$archive_sha256" == "${{ needs.package.outputs.archive_sha256 }}" ]]',
            staging,
        )
        self.assertIn(
            '[[ "$candidate_binary_sha256" == "${{ needs.package.outputs.binary_sha256 }}" ]]',
            staging,
        )
        self.assertIn(
            '[[ "$candidate_bundle_sha256" == "${{ needs.package.outputs.registry_bundle_sha256 }}" ]]',
            staging,
        )
        self.assertIn("codesign --verify --strict --verbose=4", staging)
        self.assertIn("PKGLIFT_BINARY_SHA256=$candidate_binary_sha256", staging)
        self.assertIn("PKGLIFT_ARTIFACT_SOURCE_SHA=$GITHUB_SHA", staging)

    def test_acceptance_uses_reviewed_bounded_runner_interfaces(self) -> None:
        full = self.step("Accept Signed Candidate Full Migration", self.acceptance_steps)
        self.assertEqual(full["run"], "bash Scripts/run-positive-e2e-pilot.sh")
        self.assertEqual(
            full["env"],
            {"PKGLIFT_BIN": "${{ env.PKGLIFT_RELEASE_ACCEPTANCE_BIN }}"},
        )

        partial = self.step("Accept Signed Candidate Partial Migration", self.acceptance_steps)["run"]
        self.assertIn("Scripts/run-partial-migration-pilot.py", partial)
        self.assertIn("--case PartialMixed", partial)
        self.assertIn('--pkglift "$PKGLIFT_RELEASE_ACCEPTANCE_BIN"', partial)
        self.assertIn("--jobs 2", partial)

        refusal = self.step("Accept Signed Candidate Conservative Refusal", self.acceptance_steps)["run"]
        self.assertIn("Scripts/run-real-project-refusal.py", refusal)
        self.assertIn("--case hammerspoon", refusal)
        self.assertIn('--pkglift "$PKGLIFT_RELEASE_ACCEPTANCE_BIN"', refusal)

    def test_acceptance_evidence_is_separate_from_public_distribution_input(self) -> None:
        acceptance = self.step(
            "Upload Signed Candidate Acceptance Evidence", self.acceptance_steps
        )["with"]
        distribution = self.step("Upload Validated Distribution")["with"]
        self.assertEqual(
            acceptance["name"], "pkglift-release-acceptance-${{ github.sha }}"
        )
        self.assertEqual(
            distribution["name"], "pkglift-macos-arm64-${{ github.sha }}"
        )
        self.assertNotEqual(acceptance["path"], distribution["path"])
        self.assertEqual(
            distribution["path"],
            "release/pkglift-macos-arm64.tar.gz\n"
            "release/pkglift-macos-arm64.tar.gz.sha256\n",
        )

    def test_macos14_runtime_uses_same_run_exact_candidate_outputs(self) -> None:
        self.assertEqual(self.runtime["needs"], "package")
        self.assertEqual(self.runtime["runs-on"], "macos-14")
        self.assertEqual(self.runtime["timeout-minutes"], 15)
        self.assertNotIn("if", self.runtime)
        for step in self.runtime["steps"]:
            self.assertNotIn("continue-on-error", step)
        self.assertEqual(
            self.package["outputs"],
            {
                "archive_sha256": "${{ steps.distribution_archive.outputs.archive_sha256 }}",
                "binary_sha256": "${{ steps.signing_identity.outputs.binary_sha256 }}",
                "registry_bundle_sha256": "${{ steps.signing_identity.outputs.registry_bundle_sha256 }}",
                "version": "${{ steps.version_contract.outputs.version }}",
            },
        )
        download = next(
            step
            for step in self.runtime["steps"]
            if step.get("name") == "Download Exact Signed Candidate"
        )
        self.assertEqual(
            download["uses"],
            "actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c",
        )
        self.assertEqual(
            download["with"]["name"], "pkglift-macos-arm64-${{ github.sha }}"
        )
        runtime = next(
            step
            for step in self.runtime["steps"]
            if step.get("name") == "Accept Signed Candidate on Observed macOS 14 Host"
        )["run"]
        for binding in (
            '--archive-sha256 "${{ needs.package.outputs.archive_sha256 }}"',
            '--binary-sha256 "${{ needs.package.outputs.binary_sha256 }}"',
            '--source-commit "${{ github.sha }}"',
            '--version "${{ needs.package.outputs.version }}"',
            "--required-macos-major 14",
            "--fixture Fixtures/MixedLanguageSDWebImage",
        ):
            with self.subTest(binding=binding):
                self.assertIn(binding, runtime)


if __name__ == "__main__":
    unittest.main()
