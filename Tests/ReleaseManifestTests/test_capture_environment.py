import importlib.util
import subprocess
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[2] / "Scripts" / "capture-environment.py"
SPEC = importlib.util.spec_from_file_location("capture_environment", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
capture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capture)


class CaptureEnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.outputs = {
            ("git", "rev-parse", "--verify", "HEAD"): (0, "a" * 40),
            ("git", "diff", "--quiet", "--ignore-submodules=none", "HEAD", "--"): (0, ""),
            ("sw_vers", "-productVersion"): (0, "15.7.9"),
            ("sw_vers", "-buildVersion"): (0, "24G830"),
            ("xcodebuild", "-version"): (0, "Xcode 16.4\nBuild version 16F6"),
            ("swift", "--version"): (
                0,
                "Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)\n"
                "Target: arm64-apple-macosx15.0",
            ),
            ("pod", "--version"): (0, "1.17.0"),
            ("xcrun", "--sdk", "macosx", "--show-sdk-version"): (0, "15.5"),
            ("xcrun", "--sdk", "macosx", "--show-sdk-build-version"): (0, "24F74"),
            ("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"): (0, "18.5"),
            ("xcrun", "--sdk", "iphonesimulator", "--show-sdk-build-version"): (0, "22F76"),
        }

    @staticmethod
    def resolver(executable):
        return executable

    def runner(self, command, cwd, timeout):
        self.assertEqual(capture.COMMAND_TIMEOUT_SECONDS, timeout)
        self.assertEqual(SCRIPT.parent.parent, cwd)
        returncode, stdout = self.outputs[tuple(command)]
        return subprocess.CompletedProcess(command, returncode, stdout, "ignored stderr")

    @mock.patch.object(capture.platform, "system", return_value="Darwin")
    @mock.patch.object(capture.platform, "machine", return_value="arm64")
    def test_complete_record_has_bounded_versions_and_repository_state(self, _machine, _system):
        document = capture.capture_environment(
            runner=self.runner,
            resolver=self.resolver,
            now=lambda: datetime(2026, 9, 16, 8, 30, tzinfo=timezone.utc),
        )

        self.assertEqual(1, document["schemaVersion"])
        self.assertEqual("2026-09-16T08:30:00Z", document["capturedAt"])
        self.assertTrue(document["metadataOnly"])
        self.assertEqual("complete", document["captureStatus"])
        self.assertEqual(
            {"status": "passed", "commit": "a" * 40, "trackedChanges": False},
            document["repository"],
        )
        self.assertEqual(
            {"status": "passed", "version": "15.7.9", "build": "24G830"},
            document["system"]["macOS"],
        )
        self.assertEqual("arm64", document["system"]["machine"])
        self.assertEqual(
            ["Xcode 16.4", "Build version 16F6"],
            document["commands"]["xcodebuildVersion"]["versionOutput"],
        )
        self.assertNotIn("stderr", str(document).lower())

    @mock.patch.object(capture.platform, "system", return_value="Darwin")
    def test_missing_pod_is_explicitly_unavailable(self, _system):
        document = capture.capture_environment(
            runner=self.runner,
            resolver=lambda executable: None if executable == "pod" else executable,
        )

        self.assertEqual("incomplete", document["captureStatus"])
        self.assertEqual(
            {"status": "unavailable", "exitCode": None, "versionOutput": []},
            document["commands"]["cocoaPodsVersion"],
        )

    @mock.patch.object(capture.platform, "system", return_value="Darwin")
    def test_timeout_and_unexpected_output_do_not_leak_raw_text(self, _system):
        def unsafe_runner(command, cwd, timeout):
            if tuple(command) == ("swift", "--version"):
                raise subprocess.TimeoutExpired(command, timeout, stderr="/Users/alex/secret")
            if tuple(command) == ("xcodebuild", "-version"):
                return subprocess.CompletedProcess(
                    command, 0, "Xcode 16.4\n/Users/alex/secret", "TOKEN=secret"
                )
            return self.runner(command, cwd, timeout)

        document = capture.capture_environment(
            runner=unsafe_runner,
            resolver=self.resolver,
        )

        self.assertEqual("timedOut", document["commands"]["swiftVersion"]["status"])
        self.assertEqual("failed", document["commands"]["xcodebuildVersion"]["status"])
        serialized = str(document)
        self.assertNotIn("/Users/alex", serialized)
        self.assertNotIn("TOKEN", serialized)


if __name__ == "__main__":
    unittest.main()
