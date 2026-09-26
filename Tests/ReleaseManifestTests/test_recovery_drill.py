import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/run-recovery-drill.py"
SPEC = importlib.util.spec_from_file_location("recovery_drill", SCRIPT)
recovery = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(recovery)


class RecoveryDrillSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def tree(self, name):
        root = self.root / name
        root.mkdir()
        (root / "Podfile").write_text("pod 'KeychainAccess'\n")
        project = root / recovery.PROJECT
        project.mkdir()
        (project / "project.pbxproj").write_text("project\n")
        return root

    def test_snapshot_rejects_absolute_escaping_and_special_entries(self):
        outside = self.root / "outside"
        outside.mkdir()
        for name, maker in [
            ("absolute", lambda root: (root / "link").symlink_to("/tmp")),
            ("escaping", lambda root: (root / "link").symlink_to("../outside")),
            ("fifo", lambda root: os.mkfifo(root / "pipe")),
        ]:
            with self.subTest(name=name):
                root = self.tree(name)
                maker(root)
                with self.assertRaises(RuntimeError):
                    recovery.snapshot(root)

    def test_snapshot_distinguishes_file_bytes_modes_and_link_target(self):
        root = self.tree("state")
        payload = root / "payload"
        payload.write_bytes(b"one")
        payload.chmod(0o600)
        (root / "link").symlink_to("payload")
        initial = recovery.snapshot(root)

        payload.write_bytes(b"two")
        bytes_changed = recovery.snapshot(root)
        self.assertNotEqual(initial["payload"], bytes_changed["payload"])

        payload.chmod(0o644)
        mode_changed = recovery.snapshot(root)
        self.assertNotEqual(bytes_changed["payload"], mode_changed["payload"])

        (root / "link").unlink()
        (root / "other").write_text("other")
        (root / "link").symlink_to("other")
        link_changed = recovery.snapshot(root)
        self.assertNotEqual(mode_changed["link"], link_changed["link"])
        self.assertEqual(link_changed["link"], ["symlink", "other"])

    def test_restore_publishes_staging_only_after_incident(self):
        baseline = self.tree("baseline")
        expected = recovery.snapshot(baseline)
        consumer_parent = self.root / "scenario"
        consumer_parent.mkdir()
        consumer = consumer_parent / "consumer"
        shutil_copy = recovery.shutil.copytree
        shutil_copy(baseline, consumer, symlinks=True)

        renames = []
        original_rename = Path.rename

        def recording_rename(path, target):
            renames.append((path.name, Path(target).name))
            return original_rename(path, target)

        with mock.patch.object(Path, "rename", recording_rename):
            recovery.restore_baseline(baseline, expected, consumer)

        self.assertEqual(renames, [("consumer", "incident"), ("restoring", "consumer")])
        self.assertTrue((consumer_parent / "consumer").is_dir())
        self.assertTrue((consumer_parent / "incident").is_dir())
        self.assertFalse((consumer_parent / "restoring").exists())

    def test_restore_copy_failure_preserves_incident_and_never_overwrites_consumer(self):
        baseline = self.tree("baseline")
        expected = recovery.snapshot(baseline)
        parent = self.root / "copy-failure"
        parent.mkdir()
        consumer = parent / "consumer"
        recovery.shutil.copytree(baseline, consumer, symlinks=True)
        before = recovery.snapshot(consumer)

        def partial_copy(source, destination, **_):
            Path(destination).mkdir()
            (Path(destination) / "partial-copy-marker").write_text("partial")
            raise OSError("copy failure")

        with mock.patch.object(recovery.shutil, "copytree", side_effect=partial_copy):
            with self.assertRaises(OSError):
                recovery.restore_baseline(baseline, expected, consumer)

        self.assertFalse(consumer.exists())
        self.assertTrue((parent / "restoring" / "partial-copy-marker").is_file())
        self.assertEqual(recovery.snapshot(parent / "incident"), before)

    def test_restore_rejects_bad_baseline_destinations_and_unsafe_consumer_before_overwrite(self):
        baseline = self.tree("baseline")
        expected = recovery.snapshot(baseline)

        cases = []
        corrupted = self.root / "corrupted"
        recovery.shutil.copytree(baseline, corrupted, symlinks=True)
        (corrupted / "Podfile").write_text("changed\n")
        cases.append((corrupted, expected, "corrupted"))

        for label in ("incident", "restoring"):
            clean = self.tree("baseline-" + label)
            parent = self.root / ("existing-" + label)
            parent.mkdir()
            consumer = parent / "consumer"
            recovery.shutil.copytree(clean, consumer, symlinks=True)
            (parent / label).mkdir()
            cases.append((clean, recovery.snapshot(clean), "existing-" + label))

        for baseline_case, expected_case, label in cases:
            with self.subTest(case=label):
                if label == "corrupted":
                    parent = self.root / "corrupted-parent"
                    parent.mkdir()
                    consumer = parent / "consumer"
                    recovery.shutil.copytree(baseline, consumer, symlinks=True)
                else:
                    parent = self.root / label
                    consumer = parent / "consumer"
                before = recovery.snapshot(consumer)
                with self.assertRaises(RuntimeError):
                    recovery.restore_baseline(baseline_case, expected_case, consumer)
                self.assertEqual(recovery.snapshot(consumer), before)

        safe_baseline = self.tree("safe-baseline")
        parent = self.root / "unsafe-consumer"
        parent.mkdir()
        outside = self.tree("outside")
        consumer = parent / "consumer"
        consumer.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(RuntimeError):
            recovery.restore_baseline(safe_baseline, recovery.snapshot(safe_baseline), consumer)
        self.assertTrue(consumer.is_symlink())
        self.assertFalse((parent / "incident").exists())

    def test_completed_receipt_requires_schema_outcome_files_and_exact_backup_path(self):
        consumer = self.tree("completed")
        backup = consumer / ".pkglift" / "backup"
        backup.mkdir(parents=True)
        receipt = backup / ".pkglift-completed.json"
        valid = {
            "schemaVersion": 1,
            "outcome": "rolledBack",
            "backupDirectory": str(backup.resolve()),
            "files": sorted(str((consumer / item).resolve()) for item in ("Podfile", recovery.PROJECT)),
        }
        receipt.write_text(json.dumps(valid))
        self.assertEqual(len(recovery.check_completed(consumer, "rolledBack")), 64)

        for key, value in [
            ("schemaVersion", 2),
            ("outcome", "applied"),
            ("backupDirectory", str(self.root / "other")),
            ("files", []),
        ]:
            with self.subTest(key=key):
                record = dict(valid)
                record[key] = value
                receipt.write_text(json.dumps(record))
                with self.assertRaises(RuntimeError):
                    recovery.check_completed(consumer, "rolledBack")

        receipt.write_text(json.dumps(valid))
        receipt.unlink()
        receipt.symlink_to(self.root / "outside-receipt")
        with self.assertRaises(RuntimeError):
            recovery.check_completed(consumer, "rolledBack")

    def test_main_rejects_output_inside_repository_before_creating_it(self):
        unsafe_output = ROOT / "recovery-output-must-not-exist"
        self.assertFalse(unsafe_output.exists())
        build_receipt = self.root / "existing-receipt.json"
        build_receipt.write_text("{}")
        arguments = [
            "run-recovery-drill.py", "--output", str(unsafe_output),
            "--pkglift", str(self.root / "not-used"),
            "--signal-test-bundle", str(self.root / "not-used.xctest"),
            "--build-receipt", str(build_receipt),
        ]
        with mock.patch("sys.argv", arguments), self.assertRaises(RuntimeError):
            recovery.main()
        self.assertFalse(unsafe_output.exists())

    def test_main_rejects_bad_build_provenance_before_creating_output(self):
        artifacts = self.root / "artifacts"
        artifacts.mkdir()
        binary = artifacts / "pkglift"
        binary.write_bytes(b"binary")
        bundle = artifacts / "PkgLiftCLITests.xctest"
        bundle.mkdir()
        receipt = self.root / "receipt.json"
        receipt.write_text(json.dumps({"exitCode": 0, "sourceInputs": {}, "buildsBothArtifacts": True}))
        output = self.root / "must-not-exist"
        arguments = [
            "run-recovery-drill.py", "--output", str(output), "--pkglift", str(binary),
            "--signal-test-bundle", str(bundle), "--build-receipt", str(receipt),
        ]
        with mock.patch("sys.argv", arguments), self.assertRaises(RuntimeError):
            recovery.main()
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
