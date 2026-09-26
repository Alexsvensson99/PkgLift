import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("build_recovery_inputs", ROOT / "Scripts/build-recovery-inputs.py")
builder = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(builder)


class BuildRecoveryInputsTests(unittest.TestCase):
    def test_rejects_existing_or_outside_scratch_and_cache_before_output_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scratch = root / "scratch"
            cache = root / "cache"
            scratch.mkdir()
            cache.mkdir()
            existing = root / "existing"
            existing.mkdir()
            outside = root / "outside"
            with self.assertRaises(RuntimeError):
                builder.main(["--output", str(existing), "--scratch-path", str(scratch), "--cache-path", str(cache)])
            output = root / "new-output"
            with self.assertRaises(RuntimeError):
                builder.main(["--output", str(output), "--scratch-path", str(outside), "--cache-path", str(cache)])
            self.assertFalse(output.exists())

    def test_failed_build_receipt_never_claims_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "new-output"
            scratch = root / "scratch"
            cache = root / "cache"
            scratch.mkdir()
            cache.mkdir()
            failed = mock.Mock()
            failed.wait.return_value = 9
            with mock.patch.object(builder.subprocess, "Popen", return_value=failed):
                with self.assertRaises(RuntimeError):
                    builder.main(["--output", str(output), "--scratch-path", str(scratch), "--cache-path", str(cache)])
            receipt = json.loads((output / "build-receipt.json").read_text())
            self.assertEqual(receipt["exitCode"], 9)
            self.assertFalse(receipt["buildsBothArtifacts"])
            self.assertEqual(receipt["status"], "failed")

    def test_success_receipt_binds_both_artifacts_and_source_change_refuses_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scratch = root / "scratch"
            cache = root / "cache"
            scratch.mkdir()
            cache.mkdir()
            product = scratch / "arm64-apple-macosx" / "debug"
            product.mkdir(parents=True)
            (product / "pkglift").write_bytes(b"binary")
            (product / "PkgLiftCLITests.xctest").mkdir()

            def process_for(command, **kwargs):
                if "--show-bin-path" in command:
                    kwargs["stdout"].write((str(product) + "\n").encode())
                process = mock.Mock()
                process.wait.return_value = 0
                return process

            output = root / "success"
            with mock.patch.object(builder.subprocess, "Popen", side_effect=process_for):
                builder.main(["--output", str(output), "--scratch-path", str(scratch), "--cache-path", str(cache)])
            receipt = json.loads((output / "build-receipt.json").read_text())
            self.assertTrue(receipt["buildsBothArtifacts"])
            self.assertEqual(receipt["exitCode"], 0)
            self.assertEqual(len(receipt["binarySHA256"]), 64)
            self.assertEqual(len(receipt["signalTestBundleSHA256"]), 64)

            changed_output = root / "changed"
            values = [{"same": "before"}, {"different": "after"}, {"different": "after"}]
            with mock.patch.object(builder.subprocess, "Popen", side_effect=process_for), \
                 mock.patch.object(builder.recovery, "source_inputs", side_effect=values), \
                 self.assertRaises(RuntimeError):
                builder.main(["--output", str(changed_output), "--scratch-path", str(scratch), "--cache-path", str(cache)])
            changed = json.loads((changed_output / "build-receipt.json").read_text())
            self.assertFalse(changed["buildsBothArtifacts"])
            self.assertEqual(changed["status"], "failed")


if __name__ == "__main__":
    unittest.main()
