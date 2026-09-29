"""Fail-closed acceptance boundaries for exact signed candidate runtime."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("candidate_runtime", ROOT / "Scripts/verify-candidate-runtime.py")
runtime = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runtime)
HOST = {"system": "Darwin", "macOSVersion": "14.8.9", "macOSBuild": "unknown", "cpu": "arm64",
        "requiredMacOSMajor": 14, "qualifiesRequiredHost": True}
ENTRY = {"podName": "SDWebImage", "classification": "AUTO", "targetName": "PkgLiftMixedFixture",
         "packageCandidate": {"products": ["SDWebImage"]},
         "targetSourceProfile": {"completeness": "complete", "languages": ["swift", "objectiveC"]}}
ANALYSIS = {"candidates": [{"pod": {"name": "SDWebImage", "isDirect": True}, "classification": "AUTO"}]}


class CandidateRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / "output"
        self.output.mkdir()
        self.binary_bytes = b"test-only executable bytes"
        self.archive = self.root / "candidate.tar.gz"
        self.write_archive()
        self.args = argparse.Namespace(archive=self.archive, fixture=ROOT / "Fixtures/MixedLanguageSDWebImage",
            output_dir=self.output, archive_sha256=runtime.shared.sha256_file(self.archive),
            binary_sha256=hashlib.sha256(self.binary_bytes).hexdigest(), source_commit="a" * 40,
            version="1.0.0", required_macos_major=14)
        self.calls = []
        self.corrupt_dry_run = False
        self.corrupt_apply = False

    def write_archive(self, unsafe=False):
        with tarfile.open(self.archive, "w:gz") as archive:
            for name, data in [("pkglift", self.binary_bytes),
                               ("PkgLift_PkgLiftRegistry.bundle/registry.yml", b"fixture")]:
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.mode = 0o755 if name == "pkglift" else 0o644
                archive.addfile(info, io.BytesIO(data))
            if unsafe:
                info = tarfile.TarInfo("PkgLift_PkgLiftRegistry.bundle/link")
                info.type = tarfile.SYMTYPE
                info.linkname = "../../escape"
                archive.addfile(info)

    def command(self, command, cwd):
        self.calls.append(command)
        stdout = ""
        if command[0] == "/usr/bin/sw_vers":
            stdout = "23J100\n"
        elif command[0] == "/usr/bin/xattr" and command[1] == "-p":
            stdout = "0083;0;PkgLiftCandidateRuntime;"
        elif command[0] == "/usr/bin/git" and "init" in command:
            (Path(command[-1]) / ".git").mkdir()
        elif Path(command[0]).name == "pkglift":
            action = command[1]
            if action == "version":
                stdout = "1.0.0\n"
            elif action == "analyze":
                stdout = json.dumps(ANALYSIS)
            elif action == "plan":
                (cwd / ".pkglift").mkdir()
                (cwd / ".pkglift/plan.json").write_text(json.dumps({"entries": [ENTRY]}))
            elif action == "migrate":
                if "--apply" in command:
                    podfile = cwd / "Podfile"
                    podfile.write_bytes(podfile.read_bytes().replace(
                        b"  pod 'SDWebImage', '5.18.1', :modular_headers => true\n", b""))
                    with (cwd / "PkgLiftMixedFixture.xcodeproj/project.pbxproj").open("a") as handle:
                        handle.write("\n// simulated structural mutation\n")
                    if self.corrupt_apply:
                        (cwd / "App/unexpected.swift").write_text("unexpected")
                elif self.corrupt_dry_run:
                    (cwd / "Podfile").write_text("unexpected dry-run mutation")
            elif action == "verify":
                stdout = '{"passed": true, "checks": []}'
        return {"status": "passed", "exitCode": 0}, stdout

    def verify(self):
        with mock.patch.object(runtime, "host_record", return_value=dict(HOST)), \
             mock.patch.object(runtime.shared, "command_result", side_effect=self.command):
            return runtime.verify(self.args, self.output)

    def test_valid_flow_binds_identity_and_structural_scope(self):
        summary = self.verify()
        self.assertEqual("passed", summary["status"])
        self.assertEqual(self.args.binary_sha256, summary["binarySHA256"])
        self.assertEqual("14.8.9", summary["host"]["macOSVersion"])
        self.assertFalse(summary["consumerBuildTested"])
        self.assertTrue(summary["dryRunUnchanged"])
        self.assertTrue(any("--apply" in command for command in self.calls))
        self.assertFalse(any("--allow-dirty" in command for command in self.calls))

    def test_wrong_archive_hash_prevents_all_command_execution(self):
        self.args.archive_sha256 = "0" * 64
        with self.assertRaisesRegex(runtime.VerificationError, "Archive SHA-256"):
            self.verify()
        self.assertEqual([], self.calls)

    def test_wrong_binary_hash_prevents_signature_and_candidate_execution(self):
        self.args.binary_sha256 = "0" * 64
        with self.assertRaisesRegex(runtime.VerificationError, "Binary SHA-256"):
            self.verify()
        self.assertEqual([["/usr/bin/sw_vers", "-buildVersion"]], self.calls)

    def test_unsafe_archive_refuses_before_candidate_execution(self):
        self.write_archive(unsafe=True)
        self.args.archive_sha256 = runtime.shared.sha256_file(self.archive)
        with self.assertRaisesRegex(runtime.VerificationError, "unsupported member type"):
            self.verify()
        self.assertFalse(any(Path(command[0]).name == "pkglift" for command in self.calls))

    def test_mutating_dry_run_prevents_apply(self):
        self.corrupt_dry_run = True
        with self.assertRaisesRegex(runtime.VerificationError, "Dry run changed"):
            self.verify()
        self.assertFalse(any("--apply" in command for command in self.calls))

    def test_unexpected_apply_mutation_fails_acceptance(self):
        self.corrupt_apply = True
        with self.assertRaisesRegex(runtime.VerificationError, "exactly the reviewed"):
            self.verify()

    def test_extra_auto_entry_is_rejected(self):
        with self.assertRaisesRegex(runtime.VerificationError, "AUTO set"):
            runtime.validate_auto(ANALYSIS, {"entries": [ENTRY, dict(ENTRY, podName="Unexpected")]})

    def test_other_host_cannot_be_accepted(self):
        with mock.patch.object(runtime, "host_record", return_value=dict(HOST, qualifiesRequiredHost=False)), \
             mock.patch.object(runtime.shared, "command_result") as command:
            with self.assertRaisesRegex(runtime.VerificationError, "Host does not match"):
                runtime.verify(self.args, self.output)
            command.assert_not_called()

    def test_missing_hash_is_not_an_optional_check(self):
        self.args.binary_sha256 = ""
        with self.assertRaisesRegex(runtime.VerificationError, "SHA-256 identities"):
            self.verify()
        self.assertEqual([], self.calls)

    def test_existing_output_is_preserved(self):
        sentinel = self.output / "summary.json"
        sentinel.write_text("keep")
        with mock.patch.object(runtime, "parser") as parser, mock.patch("sys.stdout"):
            parser.return_value.parse_args.return_value = self.args
            self.assertEqual(1, runtime.main())
        self.assertEqual("keep", sentinel.read_text())


if __name__ == "__main__":
    unittest.main()
