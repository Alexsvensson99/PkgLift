"""Offline regressions for registry-consumer pilot admission guards."""
import importlib.util
import json
import os
import plistlib
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


class MigratedPodfileTests(unittest.TestCase):
    @staticmethod
    def declaration(name, version):
        return f"  pod '{name}', '{version}', :modular_headers => true\n".encode()

    def original_podfile(self, name, version):
        return (
            b"platform :ios, '15.0'\n"
            + f"target 'Swift{name}' do\n".encode()
            + self.declaration(name, version)
            + b"end\n"
        )

    def verify(self, original, migrated, name, version):
        return pilot.verify_migrated_podfile(original, migrated, name, version)

    def test_accepts_each_reviewed_target_when_only_its_pod_declaration_is_removed(self):
        for name, version in (("KeychainAccess", "4.2.2"), ("DeviceKit", "5.8.0"), ("CryptoSwift", "1.10.0")):
            with self.subTest(name=name):
                original = self.original_podfile(name, version)
                expected = original.replace(self.declaration(name, version), b"")
                self.assertIsNone(self.verify(original, expected, name, version))

    def test_rejects_retained_or_changed_pod_declaration(self):
        name, version = "DeviceKit", "5.8.0"
        original = self.original_podfile(name, version)
        declaration = self.declaration(name, version)
        variants = {
            "retained": original,
            "changed-version": original.replace(declaration, self.declaration(name, "5.8.1")),
            "changed-options": original.replace(declaration, b"  pod 'DeviceKit', '5.8.0'\n"),
        }
        for label, migrated in variants.items():
            with self.subTest(label=label):
                with self.assertRaises(RuntimeError):
                    self.verify(original, migrated, name, version)

    def test_rejects_any_unrelated_podfile_change(self):
        name, version = "KeychainAccess", "4.2.2"
        original = self.original_podfile(name, version)
        expected = original.replace(self.declaration(name, version), b"")
        variants = {
            "target": expected.replace(b"SwiftKeychainAccess", b"SwiftDifferentTarget"),
            "platform": expected.replace(b"'15.0'", b"'16.0'"),
        }
        for label, migrated in variants.items():
            with self.subTest(label=label):
                with self.assertRaises(RuntimeError):
                    self.verify(original, migrated, name, version)

    def test_rejects_original_without_exactly_one_expected_declaration(self):
        name, version = "DeviceKit", "5.8.0"
        declaration = self.declaration(name, version)
        originals = {
            "missing": b"platform :ios, '15.0'\ntarget 'SwiftDeviceKit' do\nend\n",
            "duplicate": b"platform :ios, '15.0'\n" + declaration + declaration + b"end\n",
        }
        for label, original in originals.items():
            with self.subTest(label=label):
                with self.assertRaises(RuntimeError):
                    self.verify(original, original.replace(declaration, b""), name, version)


class SourceInventoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pkglift-source-inventory-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "Sources/CryptoSwift/SHA2.swift"
        self.source.parent.mkdir(parents=True)
        self.source.write_text("public struct SHA2 {}")
        self.other = self.source.with_name("AES.swift")
        self.other.write_text("public struct AES {}")
        self.expected = {str(p.relative_to(self.root)): pilot.git_blob_digest(p)
                         for p in (self.source, self.other)}

    def verify(self):
        return pilot.verify_source_inventory(self.root, self.expected)

    def test_accepts_all_reviewed_sources(self):
        self.assertIsNone(self.verify())

    def test_rejects_changed_file_even_when_probe_source_is_unchanged(self):
        self.other.write_text("public struct DifferentAES {}")
        with self.assertRaisesRegex(RuntimeError, "differs from reviewed revision"):
            self.verify()

    def test_rejects_missing_source(self):
        self.other.rename(self.other.with_suffix(".txt"))
        with self.assertRaisesRegex(RuntimeError, "differs from reviewed revision"):
            self.verify()

    def test_rejects_extra_compiled_source(self):
        self.source.with_name("Unexpected.swift").write_text("struct Extra {}")
        with self.assertRaisesRegex(RuntimeError, "differs from reviewed revision"):
            self.verify()

    def test_rejects_symlinked_source_directory(self):
        (self.source.parent / "linked").symlink_to(self.source.parent, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "Symlink"):
            self.verify()

    def test_rejects_symlinked_source_root(self):
        moved = self.root / "moved"
        self.source.parent.rename(moved)
        (self.root / "Sources/CryptoSwift").symlink_to(moved, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "Unsafe"):
            self.verify()

    def test_git_blob_identity_uses_git_header(self):
        path = self.root / "empty"
        path.write_bytes(b"")
        self.assertEqual(pilot.git_blob_digest(path), "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391")


class RequiredPrivacyManifestTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pkglift-privacy-guard-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.relative = "CryptoSwift_CryptoSwiftResources.bundle/PrivacyInfo.xcprivacy"
        self.expected = {"NSPrivacyTracking": False, "NSPrivacyCollectedDataTypes": []}

    def write(self, relative, value):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(plistlib.dumps(value))
        return path

    def verify(self):
        return pilot.verify_required_privacy_manifest(self.root, self.relative, self.expected)

    def test_accepts_expected_named_bundle_with_equal_plist_semantics(self):
        self.write(self.relative, self.expected)
        self.assertEqual(self.verify(), self.relative)

    def test_rejects_missing_resource(self):
        with self.assertRaisesRegex(RuntimeError, "Missing required privacy resource"):
            self.verify()

    def test_unrelated_manifest_does_not_satisfy_required_resource(self):
        self.write("Unrelated.bundle/PrivacyInfo.xcprivacy", self.expected)
        with self.assertRaisesRegex(RuntimeError, "Missing required privacy resource"):
            self.verify()

    def test_rejects_changed_privacy_semantics(self):
        self.write(self.relative, {**self.expected, "NSPrivacyTracking": True})
        with self.assertRaisesRegex(RuntimeError, "semantics changed"):
            self.verify()

    def test_rejects_wrong_plist_value_type_even_when_python_compares_equal(self):
        self.write(self.relative, {**self.expected, "NSPrivacyTracking": 0})
        with self.assertRaisesRegex(RuntimeError, "semantics changed"):
            self.verify()

    def test_rejects_resource_symlink(self):
        other = self.write("elsewhere/PrivacyInfo.xcprivacy", self.expected)
        target = self.root / self.relative
        target.parent.mkdir()
        target.symlink_to(other)
        with self.assertRaisesRegex(RuntimeError, "Symlink"):
            self.verify()

    def test_rejects_bundle_symlink(self):
        self.write("elsewhere/PrivacyInfo.xcprivacy", self.expected)
        (self.root / Path(self.relative).parent).symlink_to(self.root / "elsewhere", target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "Symlink"):
            self.verify()

    def test_rejects_invalid_plist(self):
        path = self.write(self.relative, self.expected)
        path.write_bytes(b"not a plist")
        with self.assertRaises(plistlib.InvalidFileException):
            self.verify()

    def test_rejects_resource_directory(self):
        (self.root / self.relative).mkdir(parents=True)
        with self.assertRaisesRegex(RuntimeError, "Missing required privacy resource"):
            self.verify()

    def test_rejects_absolute_and_escaping_paths(self):
        for relative in ("/PrivacyInfo.xcprivacy", "../PrivacyInfo.xcprivacy"):
            with self.subTest(relative=relative), self.assertRaisesRegex(RuntimeError, "remain inside"):
                pilot.verify_required_privacy_manifest(self.root, relative, self.expected)


if __name__ == "__main__":
    unittest.main()
