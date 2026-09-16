"""Focused contracts for the bounded published-runtime qualifier."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts" / "verify-runtime-environment.py"
WORKFLOW = ROOT / ".github/workflows/environment-qualification.yml"
SPEC = importlib.util.spec_from_file_location("runtime_environment", SCRIPT)
runtime = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(runtime)


class RuntimeEnvironmentTests(unittest.TestCase):
    @mock.patch.object(runtime.platform, "machine", return_value="arm64")
    @mock.patch.object(runtime.platform, "mac_ver", return_value=("14.8", ("", "", ""), ""))
    @mock.patch.object(runtime.platform, "system", return_value="Darwin")
    def test_macos_14_arm64_qualifies(self, _system, _version, _machine):
        record = runtime.host_record()
        self.assertTrue(record["qualifiesMinimumHost"])
        self.assertEqual("arm64", record["cpu"])

    @mock.patch.object(runtime.platform, "machine", return_value="x86_64")
    @mock.patch.object(runtime.platform, "mac_ver", return_value=("14.8", ("", "", ""), ""))
    @mock.patch.object(runtime.platform, "system", return_value="Darwin")
    @mock.patch.object(runtime, "command_result", return_value=({"status": "passed", "exitCode": 0}, "24G830\n"))
    def test_other_cpu_refuses_by_default_and_writes_owned_summary(self, _command, _system, _version, _machine):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "owned-output"
            arguments = [str(SCRIPT), "--archive", "missing.tar.gz", "--output-dir", str(output), "--fixture", "fixture"]
            with mock.patch("sys.argv", arguments), mock.patch("sys.stdout") as stdout:
                self.assertEqual(1, runtime.main())
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual("failed", summary["status"])
            self.assertFalse(summary["host"]["qualifiesMinimumHost"])
            self.assertIn("macOS 14 arm64", summary["failure"])
            self.assertEqual(json.loads(stdout.write.call_args[0][0])["status"], "failed")

    def test_existing_output_directory_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "existing-output"
            output.mkdir()
            sentinel = output / "sentinel.txt"
            sentinel.write_text("preserve", encoding="utf-8")
            arguments = [str(SCRIPT), "--archive", "missing.tar.gz", "--output-dir", str(output), "--fixture", "fixture"]
            with mock.patch("sys.argv", arguments), mock.patch("sys.stdout"):
                self.assertEqual(1, runtime.main())
            self.assertEqual("preserve", sentinel.read_text(encoding="utf-8"))
            self.assertFalse((output / "summary.json").exists())

    def test_workflow_is_bounded_to_the_dedicated_runner_and_evidence(self):
        contents = WORKFLOW.read_text(encoding="utf-8")
        for required in (
            "runs-on: macos-14",
            "timeout-minutes: 10",
            "contents: read",
            "persist-credentials: false",
            "--fail --location --retry 2 --connect-timeout 15 --max-time 120",
            "releases/download/v0.10.0/pkglift-macos-arm64.tar.gz",
        ):
            with self.subTest(required=required):
                self.assertIn(required, contents)
        self.assertIn("actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", contents)
        self.assertIn("actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a", contents)
        self.assertIn("retention-days: 7", contents)
        self.assertNotIn("capture-environment.py", contents)


if __name__ == "__main__":
    unittest.main()
