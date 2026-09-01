from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = ROOT / ".github" / "workflows" / "publish-release-manifest.yml"
VALIDATOR_PATH = ROOT / "Scripts" / "validate-publication-input.sh"
ARCHIVE_NAME = "pkglift-macos-arm64.tar.gz"
CHECKSUM_NAME = f"{ARCHIVE_NAME}.sha256"


class PublicationInputValidationTests(unittest.TestCase):
    def create_valid_input(self, directory: Path) -> Path:
        release = directory / "release"
        release.mkdir()
        (release / ARCHIVE_NAME).write_bytes(b"validated archive")
        (release / CHECKSUM_NAME).write_text(
            f"{'0' * 64}  {ARCHIVE_NAME}\n",
            encoding="utf-8",
        )
        return release

    def run_validator(self, release: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(VALIDATOR_PATH), str(release)],
            check=False,
            capture_output=True,
            text=True,
        )

    def test_accepts_exactly_two_nonempty_regular_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release = self.create_valid_input(Path(temporary_directory))
            result = self.run_validator(release)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_invalid_publication_entries(self) -> None:
        cases = (
            "empty_directory",
            "missing",
            "extra",
            "hidden_extra",
            "unexpected_directory",
            "empty_archive",
            "symlink_archive",
            "symlink_checksum",
            "symlink_release_directory",
        )
        for case in cases:
            with self.subTest(case=case):
                with tempfile.TemporaryDirectory() as temporary_directory:
                    directory = Path(temporary_directory)
                    release = self.create_valid_input(directory)
                    archive = release / ARCHIVE_NAME
                    checksum = release / CHECKSUM_NAME

                    if case == "empty_directory":
                        archive.unlink()
                        checksum.unlink()
                    elif case == "missing":
                        checksum.unlink()
                    elif case == "extra":
                        (release / "unexpected.txt").write_text("extra", encoding="utf-8")
                    elif case == "hidden_extra":
                        (release / ".unexpected").write_text("extra", encoding="utf-8")
                    elif case == "unexpected_directory":
                        (release / "unexpected").mkdir()
                    elif case == "empty_archive":
                        archive.write_bytes(b"")
                    elif case == "symlink_archive":
                        target = directory / "outside-archive"
                        target.write_bytes(b"validated archive")
                        archive.unlink()
                        archive.symlink_to(target)
                    elif case == "symlink_checksum":
                        target = directory / "outside-checksum"
                        target.write_text(
                            f"{'0' * 64}  {ARCHIVE_NAME}\n",
                            encoding="utf-8",
                        )
                        checksum.unlink()
                        checksum.symlink_to(target)
                    else:
                        release_link = directory / "release-link"
                        release_link.symlink_to(release, target_is_directory=True)
                        release = release_link

                    result = self.run_validator(release)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertTrue(result.stderr.strip())


class PublicationWorkflowRegressionTests(unittest.TestCase):
    def publish_job(self) -> str:
        workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        marker = "\n  publish:\n"
        self.assertIn(marker, workflow)
        return workflow.split(marker, maxsplit=1)[1]

    def test_checkout_precedes_download_validation_tag_and_release(self) -> None:
        publish_job = self.publish_job()
        markers = (
            "      - name: Checkout Validated Release Policy",
            "      - name: Download Validated Publication Input",
            "      - name: Validate Publication Input Before Tagging",
            "      - name: Recheck Distribution Checksum",
            "      - name: Atomically Create and Verify Release Tag",
            "      - name: Create GitHub Release from Verified Tag",
            "      - name: Verify Published Tag and Assets",
        )
        positions = []
        for marker in markers:
            self.assertEqual(publish_job.count(marker), 1, marker)
            positions.append(publish_job.index(marker))
        self.assertEqual(positions, sorted(positions))

        checkout = publish_job[positions[0] : positions[1]]
        self.assertIn(
            "ref: ${{ needs.validate-and-package.outputs.target_commitish }}",
            checkout,
        )
        self.assertNotIn("clean: false", checkout)

        publication_validation = publish_job[positions[2] : positions[3]]
        self.assertIn(
            "run: bash Scripts/validate-publication-input.sh release",
            publication_validation,
        )

    def test_release_action_uploads_exactly_the_validated_assets(self) -> None:
        publish_job = self.publish_job()
        release_step_start = publish_job.index(
            "      - name: Create GitHub Release from Verified Tag"
        )
        verification_step_start = publish_job.index(
            "      - name: Verify Published Tag and Assets"
        )
        release_step = publish_job[release_step_start:verification_step_start]
        files_marker = "          files: |\n"
        self.assertEqual(release_step.count(files_marker), 1)
        files_block = release_step.split(files_marker, maxsplit=1)[1].split(
            "          fail_on_unmatched_files:",
            maxsplit=1,
        )[0]
        assets = [line.strip() for line in files_block.splitlines() if line.strip()]
        self.assertEqual(
            assets,
            [
                f"release/{ARCHIVE_NAME}",
                f"release/{CHECKSUM_NAME}",
            ],
        )


if __name__ == "__main__":
    unittest.main()
