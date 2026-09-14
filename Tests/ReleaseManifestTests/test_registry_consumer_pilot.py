"""Offline regressions for registry-consumer pilot admission guards."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "Scripts/run-registry-consumer-pilot.py"
SPEC = importlib.util.spec_from_file_location("run_registry_consumer_pilot", MODULE_PATH)
pilot = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(pilot)


class RegistryConsumerPilotGuardsTests(unittest.TestCase):
    def run_guard(self, phase, fixture_kind, registry_contents, expected_message):
        with tempfile.TemporaryDirectory(prefix="pkglift-registry-guard-") as directory:
            root = Path(directory)
            workspace = root / "workspace"
            runner_temp = root / "runner-temp"
            workspace.mkdir()
            runner_temp.mkdir()
            self.create_fixture(workspace, fixture_kind)
            for relative_path, contents in registry_contents.items():
                path = workspace / relative_path
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(contents)

            environment = {
                "GITHUB_WORKSPACE": str(workspace),
                "RUNNER_TEMP": str(runner_temp),
                "GITHUB_ENV": str(root / "github.env"),
                "GITHUB_STEP_SUMMARY": str(root / "summary.md"),
            }
            with mock.patch.dict(os.environ, environment, clear=False), \
                 mock.patch.object(
                     pilot.shutil,
                     "which",
                     return_value="/usr/bin/mock-tool",
                 ) as tool_which, \
                 mock.patch.object(
                     pilot.urllib.request,
                     "urlopen",
                     side_effect=AssertionError("network must not run before an admission guard"),
                 ) as urlopen, \
                 mock.patch.object(
                     pilot.subprocess,
                     "run",
                     side_effect=AssertionError("build commands must not run before an admission guard"),
                 ) as subprocess_run, \
                 mock.patch.object(
                     sys,
                     "argv",
                     ["run-registry-consumer-pilot.py", "--case", "DeviceKit", "--phase", phase],
                 ):
                with self.assertRaisesRegex(RuntimeError, expected_message):
                    pilot.main()

            self.assertEqual(tool_which.call_args_list, [mock.call("pod"), mock.call("xcodebuild")])
            urlopen.assert_not_called()
            subprocess_run.assert_not_called()
            summaries = list(runner_temp.glob("pkglift-registry-DeviceKit-*/report/summary.json"))
            self.assertEqual(len(summaries), 1)
            self.assertEqual(json.loads(summaries[0].read_text())["status"], "incomplete")

    def create_fixture(self, workspace, fixture_kind):
        fixtures = workspace / "Fixtures"
        fixtures.mkdir()
        fixture = fixtures / "SwiftDeviceKit"
        if fixture_kind == "directory":
            fixture.mkdir()
            return
        if fixture_kind == "symlink":
            target = workspace / "fixture-target"
            target.mkdir()
            fixture.symlink_to(target, target_is_directory=True)
            return
        raise AssertionError(f"Unknown fixture kind: {fixture_kind}")

    def test_equivalence_refuses_each_existing_registry_copy_before_network_or_build(self):
        copies = (
            Path("Registry/D/DeviceKit.yml"),
            Path("Sources/PkgLiftRegistry/BundledRegistry/D/DeviceKit.yml"),
        )
        for registry_copy in copies:
            with self.subTest(registry_copy=registry_copy):
                self.run_guard(
                    phase="equivalence",
                    fixture_kind="directory",
                    registry_contents={registry_copy: "reviewed: false\n"},
                    expected_message="Equivalence must precede both registry entries",
                )

    def test_migration_requires_both_registry_copies_before_network_or_build(self):
        copies = (
            Path("Registry/D/DeviceKit.yml"),
            Path("Sources/PkgLiftRegistry/BundledRegistry/D/DeviceKit.yml"),
        )
        for registry_copy in copies:
            with self.subTest(registry_copy=registry_copy):
                self.run_guard(
                    phase="migration",
                    fixture_kind="directory",
                    registry_contents={registry_copy: "reviewed: false\n"},
                    expected_message="migration requires both entries",
                )

    def test_migration_rejects_schema_one_registry_copies_before_network_or_build(self):
        copies = {
            Path("Registry/D/DeviceKit.yml"): "schemaVersion: 1\n",
            Path("Sources/PkgLiftRegistry/BundledRegistry/D/DeviceKit.yml"): "schemaVersion: 1\n",
        }
        self.run_guard(
            phase="migration",
            fixture_kind="directory",
            registry_contents=copies,
            expected_message="Platform-constrained mappings require registry schema 2",
        )

    def test_migration_rejects_nonidentical_registry_copies_before_network_or_build(self):
        copies = {
            Path("Registry/D/DeviceKit.yml"): "schemaVersion: 2\nmetadata: primary\n",
            Path("Sources/PkgLiftRegistry/BundledRegistry/D/DeviceKit.yml"): "schemaVersion: 2\nmetadata: bundled\n",
        }
        self.run_guard(
            phase="migration",
            fixture_kind="directory",
            registry_contents=copies,
            expected_message="Registry copies differ",
        )

    def test_symlinked_fixture_root_is_refused_before_network_or_build(self):
        self.run_guard(
            phase="equivalence",
            fixture_kind="symlink",
            registry_contents={},
            expected_message="Unsafe fixture",
        )


if __name__ == "__main__":
    unittest.main()
