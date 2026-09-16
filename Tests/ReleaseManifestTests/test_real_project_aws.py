import hashlib
import importlib.util
import io
import json
import os
import stat
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/run-real-project-aws.py"
SPEC = importlib.util.spec_from_file_location("real_project_aws", SCRIPT)
aws = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(aws)


def exact_requirement(version="5.18.1"):
    return {"exact": {"_0": version}}


def package(version="5.18.1"):
    return {
        "repositoryURL": aws.PACKAGE_URL,
        "products": ["SDWebImage"],
        "versionRequirement": exact_requirement(version),
        "confidence": "verified",
        "supportedConsumerLanguages": ["swift", "objectiveC"],
        "supportedConsumerPlatforms": None,
    }


def actions(version="5.18.1"):
    return [
        {"removePod": {"name": "SDWebImage"}},
        {"addSwiftPackage": {"repositoryURL": aws.PACKAGE_URL, "requirement": exact_requirement(version)}},
        {"linkProduct": {"repositoryURL": aws.PACKAGE_URL, "productName": "SDWebImage", "targetName": aws.TARGET}},
    ]


def analysis_and_plan():
    analysis = {
        "project": {"projectPath": "/tmp/source/Grid Feed.xcodeproj",
                    "workspacePath": "/tmp/source/Grid Feed.xcworkspace"},
        "candidates": [
            {"pod": {"name": "AmazonIVSPlayer", "version": "1.40.0", "isDirect": True}, "classification": "review"},
            {"pod": {"name": "SDWebImage", "version": "5.18.1", "isDirect": True}, "classification": "auto",
             "packageCandidate": package()},
        ]
    }
    plan = {
        "projectPath": "/tmp/source/Grid Feed.xcodeproj",
        "entries": [
            {"podName": "AmazonIVSPlayer", "currentVersion": "1.40.0", "classification": "review",
             "actions": [{"manual": {"description": "Retain"}}]},
            {"podName": "SDWebImage", "currentVersion": "5.18.1", "classification": "auto", "actions": actions(),
             "targetName": aws.TARGET, "packageCandidate": package(),
             "targetSourceProfile": {"completeness": "complete", "languages": ["swift"]}},
        ]
    }
    return analysis, plan


def podspec(name):
    if name == "AmazonIVSPlayer":
        return {
            "name": name, "version": "1.40.0",
            "source": {"http": "https://player.live-video.net/1.40.0/AmazonIVSPlayer.tgz",
                       "sha256": "e7cacfbcaead184d0efca1c53d656d64ee2a46721b9097198848156a5476c5d6"},
            "vendored_frameworks": "AmazonIVSPlayer.xcframework",
        }
    return {"name": name, "version": "5.18.1", "source": {"git": aws.PACKAGE_GIT_URL, "tag": "5.18.1"}}


def project_with_phases(extra=None, framework_script=None):
    phase_ids = ["CHECK", "EMBED"]
    objects = {
        "TARGET": {"isa": "PBXNativeTarget", "name": aws.TARGET, "buildPhases": phase_ids},
        "CHECK": {"isa": "PBXShellScriptBuildPhase", "name": "[CP] Check Pods Manifest.lock",
                  "shellScript": 'diff "${PODS_PODFILE_DIR_PATH}/Podfile.lock" "${PODS_ROOT}/Manifest.lock"\n'},
        "EMBED": {"isa": "PBXShellScriptBuildPhase", "name": "[CP] Embed Pods Frameworks",
                  "shellScript": framework_script or '"${PODS_ROOT}/Target Support Files/Pods-Grid Feed/Pods-Grid Feed-frameworks.sh"\n'},
    }
    if extra:
        objects["EXTRA"] = extra
        phase_ids.append("EXTRA")
    return {"objects": objects}


class RuntimeContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.binary = self.root / "pkglift"
        self.binary.write_bytes(b"binary")
        self.binary.chmod(0o755)
        (self.root / "manifest.txt").write_text(
            "binary_sha256=" + hashlib.sha256(b"binary").hexdigest() + "\n"
            "source_sha=" + "a" * 40 + "\nrun_id=123\nproducer_run_attempt=1\n"
            "bundle_sha256=" + "b" * 64 + "\nrepository=owner/repo\n"
        )
        self.env = {
            "GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted", "RUNNER_TEMP": str(self.root),
            "PKGLIFT_BINARY_SHA256": hashlib.sha256(b"binary").hexdigest(),
            "PKGLIFT_ARTIFACT_SOURCE_SHA": "a" * 40, "GITHUB_SHA": "a" * 40,
            "PKGLIFT_ARTIFACT_RUN_ID": "123", "GITHUB_RUN_ID": "123", "PKGLIFT_ARTIFACT_RUN_ATTEMPT": "1",
            "GITHUB_REPOSITORY": "owner/repo",
        }

    def tearDown(self):
        self.temp.cleanup()

    def test_accepts_verified_hosted_contract(self):
        value = aws.validate_runtime_contract(self.binary, self.root / "new-output", self.env)
        self.assertEqual(value["artifact"]["sha256"], self.env["PKGLIFT_BINARY_SHA256"])

    def test_rejects_local_or_unverified_artifact(self):
        for key, value in [("GITHUB_ACTIONS", "false"), ("RUNNER_ENVIRONMENT", "self-hosted"),
                           ("PKGLIFT_BINARY_SHA256", "0" * 64), ("PKGLIFT_ARTIFACT_RUN_ID", "")]:
            with self.subTest(key=key), self.assertRaises(aws.QualificationError):
                aws.validate_runtime_contract(self.binary, self.root / "new-output", {**self.env, key: value})

    def test_rejects_output_outside_runner_temp_or_existing(self):
        with self.assertRaises(aws.QualificationError):
            aws.validate_runtime_contract(self.binary, Path("relative"), self.env)
        existing = self.root / "existing"
        existing.mkdir()
        with self.assertRaises(aws.QualificationError):
            aws.validate_runtime_contract(self.binary, existing, self.env)

    def test_rejects_artifact_from_a_different_workflow_run(self):
        with self.assertRaises(aws.QualificationError):
            aws.validate_runtime_contract(self.binary, self.root / "new-output", {**self.env, "GITHUB_RUN_ID": "124"})

    def test_command_environment_discards_all_inherited_git_controls(self):
        clean = aws.command_environment({"PATH": "/bin", "GIT_DIR": "/secret", "GIT_WORK_TREE": "/other",
                                         "GIT_CONFIG_KEY_0": "filter.bad.process", "GIT_EXEC_PATH": "/bad"})
        self.assertEqual(clean["PATH"], "/bin")
        self.assertNotIn("GIT_DIR", clean)
        self.assertNotIn("GIT_WORK_TREE", clean)
        self.assertNotIn("GIT_CONFIG_KEY_0", clean)
        self.assertEqual(clean["GIT_CONFIG_GLOBAL"], "/dev/null")

    def test_main_preflight_failure_never_creates_output_or_runner(self):
        output = self.root / "never-created"
        with mock.patch.object(aws, "Runner") as runner:
            code = aws.main(["--pkglift", str(self.binary), "--output", str(output)])
        self.assertEqual(code, 2)
        self.assertFalse(output.exists())
        runner.assert_not_called()


class SnapshotAndDeltaTests(unittest.TestCase):
    def test_snapshot_covers_ignored_style_files_symlinks_and_mode(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "ignored.bin"
            target.write_bytes(b"value")
            target.chmod(0o755)
            (root / "alias").symlink_to("ignored.bin")
            snap = aws.tree_snapshot(root)
            self.assertEqual(snap["alias"]["target"], "ignored.bin")
            self.assertEqual(snap["ignored.bin"]["mode"] & 0o111, 0o111)

    def test_dry_run_detects_bytes_mode_and_symlink_changes(self):
        with self.assertRaises(aws.QualificationError):
            aws.validate_dry_run({"a": {"mode": 0o644}}, {"a": {"mode": 0o755}})

    def test_dry_run_output_must_match_reviewed_action_exactly(self):
        expected = ("Dry run mode. Add --apply to execute the migration plan.\n"
                    "1 AUTO migration(s):\n"
                    f"- SDWebImage -> {aws.PACKAGE_URL}\n")
        aws.validate_dry_run_output(expected)
        with self.assertRaises(aws.QualificationError):
            aws.validate_dry_run_output(expected + "- AmazonIVSPlayer\n")

    def test_dependency_delta_allows_reviewed_paths_only(self):
        before = {"Podfile": {"sha256": "a"}, "App/View.swift": {"sha256": "a"}}
        after = {"Podfile": {"sha256": "b"}, "App/View.swift": {"sha256": "a"},
                 "Pods/Manifest.lock": {"sha256": "c"}}
        self.assertEqual(aws.validate_dependency_only_delta(before, after), ["Podfile", "Pods/Manifest.lock"])
        after["App/View.swift"] = {"sha256": "changed"}
        with self.assertRaises(aws.QualificationError):
            aws.validate_dependency_only_delta(before, after)


class IntakeTests(unittest.TestCase):
    def test_podspec_rejects_all_executable_hook_keys_recursively(self):
        for key in ("prepare_command", "script_phase", "script_phases"):
            spec = podspec("SDWebImage")
            spec["subspecs"] = [{key: "curl bad.example"}]
            with self.subTest(key=key), self.assertRaises(aws.QualificationError):
                aws.validate_podspec(spec, "SDWebImage")

    def test_podspec_rejects_changed_binary_source_or_package_tag(self):
        amazon = podspec("AmazonIVSPlayer")
        amazon["source"]["sha256"] = "0" * 64
        with self.assertRaises(aws.QualificationError):
            aws.validate_podspec(amazon, "AmazonIVSPlayer")
        sd = podspec("SDWebImage")
        sd["source"]["tag"] = "main"
        with self.assertRaises(aws.QualificationError):
            aws.validate_podspec(sd, "SDWebImage")

    def test_public_podspec_requires_raw_and_semantic_hashes(self):
        raw = json.dumps(podspec("SDWebImage")).encode()
        with mock.patch.dict(aws.PODSPEC_INPUTS["SDWebImage"],
                             {"rawSHA256": hashlib.sha256(raw).hexdigest(),
                              "rawSHA1": hashlib.sha1(raw).hexdigest(),
                              "canonicalSHA256": aws.canonical_json_sha256(json.loads(raw))}):
            _, evidence = aws.validate_public_podspec_bytes("SDWebImage", raw)
            self.assertEqual(evidence["hooks"], [])
        with self.assertRaises(aws.QualificationError):
            aws.validate_public_podspec_bytes("SDWebImage", raw)

    def test_source_intake_rejects_executable_and_symlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / aws.PROJECT).mkdir()
            (root / aws.WORKSPACE).mkdir()
            (root / aws.PROJECT / "project.pbxproj").write_text("project")
            (root / aws.WORKSPACE / "contents.xcworkspacedata").write_text("workspace")
            (root / "Podfile").write_text("pod 'AmazonIVSPlayer', '~> 1.40.0'\npod 'SDWebImage', '~> 5.0', :modular_headers => true\n")
            (root / "Podfile.lock").write_text("lock")
            (root / "LICENSE").write_text("MIT No Attribution")
            hashes = {str(path.relative_to(root)): aws.file_sha256(path) for path in root.rglob("*") if path.is_file()}
            executable = root / "run.sh"
            executable.write_text("exit 0")
            executable.chmod(0o755)
            with mock.patch.object(aws, "EXPECTED_SOURCE_HASHES", hashes), self.assertRaises(aws.QualificationError):
                aws.validate_source_intake(root)
            executable.unlink()
            (root / "alias").symlink_to("Podfile")
            with mock.patch.object(aws, "EXPECTED_SOURCE_HASHES", hashes), self.assertRaises(aws.QualificationError):
                aws.validate_source_intake(root)

    def test_archive_inventory_accepts_only_safe_xcframework_structure(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive_path = Path(temporary) / "Amazon.tgz"
            plist = __import__("plistlib").dumps({"AvailableLibraries": [{
                "LibraryIdentifier": "ios-arm64", "LibraryPath": "AmazonIVSPlayer.framework",
                "BinaryPath": "AmazonIVSPlayer.framework/AmazonIVSPlayer",
                "SupportedArchitectures": ["arm64"], "SupportedPlatform": "ios"}]})
            entries = [
                ("AmazonIVSPlayer.xcframework/Info.plist", plist, 0o644),
                ("AmazonIVSPlayer.xcframework/ios-arm64/AmazonIVSPlayer.framework/AmazonIVSPlayer",
                 bytes.fromhex("cafebabe") + b"macho", 0o644),
                ("AmazonIVSPlayer.xcframework/ios-arm64/AmazonIVSPlayer.framework/_CodeSignature/CodeResources", b"sig", 0o644),
            ]
            with tarfile.open(archive_path, "w:gz") as archive:
                for name, body, mode in entries:
                    info = tarfile.TarInfo(name)
                    info.size = len(body)
                    info.mode = mode
                    archive.addfile(info, io.BytesIO(body))
            with mock.patch.object(aws, "AMAZON_ARCHIVE_SHA256", aws.file_sha256(archive_path)):
                evidence = aws.inspect_amazon_archive(archive_path)
            self.assertEqual(evidence["sliceIdentifiers"], ["ios-arm64"])
            self.assertEqual(evidence["frameworkExecutables"], 1)

    def test_archive_inventory_rejects_escaping_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive_path = Path(temporary) / "bad.tgz"
            with tarfile.open(archive_path, "w:gz") as archive:
                info = tarfile.TarInfo("../bad")
                info.size = 1
                archive.addfile(info, io.BytesIO(b"x"))
            with mock.patch.object(aws, "AMAZON_ARCHIVE_SHA256", aws.file_sha256(archive_path)), \
                    self.assertRaises(aws.QualificationError):
                aws.inspect_amazon_archive(archive_path)

    def test_installed_podspecs_must_be_exact_and_complete(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "Pods/Local Podspecs"
            directory.mkdir(parents=True)
            documents = {name: podspec(name) for name in aws.POD_VERSIONS}
            for name, document in documents.items():
                (directory / f"{name}.podspec.json").write_text(json.dumps(document))
            patched = {name: {**value, "canonicalSHA256": aws.canonical_json_sha256(documents[name])}
                       for name, value in aws.PODSPEC_INPUTS.items()}
            with mock.patch.object(aws, "PODSPEC_INPUTS", patched):
                self.assertEqual(len(aws.validate_installed_podspecs(Path(temporary))), 2)
                (directory / "Unexpected.podspec.json").write_text("{}")
                with self.assertRaises(aws.QualificationError):
                    aws.validate_installed_podspecs(Path(temporary))

    def test_installed_amazon_payload_must_match_reviewed_archive_tree(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            payload = root / "Pods/AmazonIVSPlayer/AmazonIVSPlayer.xcframework/Info.plist"
            payload.parent.mkdir(parents=True)
            payload.write_bytes(b"plist")
            expected = {"AmazonIVSPlayer.xcframework/Info.plist":
                        {"kind": "file", "sha256": hashlib.sha256(b"plist").hexdigest()}}
            evidence = aws.validate_installed_dependency_payloads(root, None, expected, include_sd=False)
            self.assertIn("amazonPayloadTreeSHA256", evidence)
            payload.write_bytes(b"changed")
            with self.assertRaises(aws.QualificationError):
                aws.validate_installed_dependency_payloads(root, None, expected, include_sd=False)


class LockTests(unittest.TestCase):
    LOCK = """PODS:
  - AmazonIVSPlayer (1.40.0)
  - SDWebImage (5.18.1):
    - SDWebImage/Core (= 5.18.1)
  - SDWebImage/Core (5.18.1)
DEPENDENCIES:
  - AmazonIVSPlayer (= 1.40.0)
  - SDWebImage (= 5.18.1)
SPEC CHECKSUMS:
  AmazonIVSPlayer: b1dbf89d0067d016ab734dc6e7ae799ea52101cd
  SDWebImage: ebdbcebc7933a45226d9313bd0118bc052ad458b
COCOAPODS: 1.16.2
"""

    def test_exact_lock_and_metadata_only_normalization(self):
        result = aws.validate_lock(self.LOCK, {"AmazonIVSPlayer", "SDWebImage"})
        self.assertEqual(result["versions"]["SDWebImage/Core"], "5.18.1")
        aws.validate_lock_metadata_normalization(self.LOCK, self.LOCK.replace("1.16.2", "1.17.0"))

    def test_rejects_dependency_change_disguised_as_tool_normalization(self):
        with self.assertRaises(aws.QualificationError):
            aws.validate_lock_metadata_normalization(self.LOCK, self.LOCK.replace("SDWebImage (5.18.1)", "SDWebImage (5.19.0)"))

    def test_final_lock_rejects_migrated_transitive(self):
        final = self.LOCK.replace("  - SDWebImage (= 5.18.1)\n", "")
        with self.assertRaises(aws.QualificationError):
            aws.validate_lock(final, {"AmazonIVSPlayer"})

    def test_migrated_podfile_allows_only_exact_reviewed_removal(self):
        before = ("platform :ios, '14.0'\n\ntarget 'Grid Feed' do\n"
                  "    pod 'AmazonIVSPlayer', '~> 1.40.0'\n"
                  "    pod 'SDWebImage', '~> 5.0', modular_headers: true\nend\n").encode()
        after = before.replace(b"    pod 'SDWebImage', '~> 5.0', modular_headers: true\n", b"")
        aws.validate_migrated_podfile(before, after)
        with self.assertRaises(aws.QualificationError):
            aws.validate_migrated_podfile(before, after.replace(b"14.0", b"15.0"))


class PlanTests(unittest.TestCase):
    def test_accepts_exact_partial_migration(self):
        evidence = aws.validate_analysis_and_plan(*analysis_and_plan())
        self.assertEqual(evidence["auto"], ["SDWebImage"])

    def test_runtime_selection_rejects_same_named_project_outside_copy(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            analysis, plan = analysis_and_plan()
            analysis["project"] = {"projectPath": str(root / aws.PROJECT),
                                   "workspacePath": str(root / aws.WORKSPACE)}
            plan["projectPath"] = str(root / aws.PROJECT)
            aws.validate_analysis_and_plan(analysis, plan, root)
            analysis["project"]["workspacePath"] = "/tmp/other/Grid Feed.xcworkspace"
            with self.assertRaises(aws.QualificationError):
                aws.validate_analysis_and_plan(analysis, plan, root)

    def test_rejects_extra_auto_or_retained_actions(self):
        analysis, plan = analysis_and_plan()
        analysis["candidates"][0]["classification"] = "auto"
        with self.assertRaises(aws.QualificationError):
            aws.validate_analysis_and_plan(analysis, plan)
        analysis, plan = analysis_and_plan()
        plan["entries"][0]["actions"] = [{"removePod": {"name": "AmazonIVSPlayer"}}]
        with self.assertRaises(aws.QualificationError):
            aws.validate_analysis_and_plan(analysis, plan)

    def test_rejects_wrong_target_version_repo_product_profile_or_action(self):
        mutations = [
            lambda e: e.update(targetName="Other"),
            lambda e: e.update(currentVersion="5.19.0"),
            lambda e: e["packageCandidate"].update(repositoryURL="https://example.invalid/repo"),
            lambda e: e["packageCandidate"].update(products=["Other"]),
            lambda e: e.update(targetSourceProfile={"languages": ["objectiveC"]}),
            lambda e: e.update(actions=actions("5.19.0")),
        ]
        for mutation in mutations:
            analysis, plan = analysis_and_plan()
            mutation(plan["entries"][1])
            with self.subTest(mutation=mutation), self.assertRaises(aws.QualificationError):
                aws.validate_analysis_and_plan(analysis, plan)

    def test_portable_parity_ignores_only_free_text(self):
        analysis, _ = analysis_and_plan()
        portable = json.loads(json.dumps(analysis))
        portable["portableOutput"] = {"version": 1}
        portable["candidates"][1]["reasons"] = ["redacted text"]
        aws.validate_portable_parity(analysis, portable, "candidates")
        portable["candidates"][1]["classification"] = "review"
        with self.assertRaises(aws.QualificationError):
            aws.validate_portable_parity(analysis, portable, "candidates")


class PackageAndReportTests(unittest.TestCase):
    @staticmethod
    def linked_project():
        return {"rootObject": "PROJECT", "objects": {
            "PROJECT": {"isa": "PBXProject", "packageReferences": ["REF"]},
            "TARGET": {"isa": "PBXNativeTarget", "name": aws.TARGET,
                       "packageProductDependencies": ["PRODUCT"], "buildPhases": ["FRAMEWORKS", "CHECK", "EMBED"]},
            "REF": {"isa": "XCRemoteSwiftPackageReference", "repositoryURL": aws.PACKAGE_URL,
                    "requirement": {"kind": "exactVersion", "version": "5.18.1"}},
            "PRODUCT": {"isa": "XCSwiftPackageProductDependency", "productName": "SDWebImage", "package": "REF"},
            "BUILD": {"isa": "PBXBuildFile", "productRef": "PRODUCT"},
            "FRAMEWORKS": {"isa": "PBXFrameworksBuildPhase", "files": ["BUILD"]},
            "CHECK": {"isa": "PBXShellScriptBuildPhase", "name": "[CP] Check Pods Manifest.lock"},
            "EMBED": {"isa": "PBXShellScriptBuildPhase", "name": "[CP] Embed Pods Frameworks"},
        }}

    def test_linkage_requires_one_exact_package_product_and_build_file(self):
        self.assertEqual(aws.validate_project_linkage(self.linked_project())["linkedCount"], 1)
        document = self.linked_project()
        document["objects"]["REF"]["requirement"]["version"] = "5.19.0"
        with self.assertRaises(aws.QualificationError):
            aws.validate_project_linkage(document)
        document = self.linked_project()
        document["objects"]["OTHER"] = {"isa": "PBXBuildFile", "productRef": "PRODUCT"}
        with self.assertRaises(aws.QualificationError):
            aws.validate_project_linkage(document)

    def test_resolved_pin_requires_exact_version_and_revision(self):
        document = {"pins": [{"location": aws.PACKAGE_URL,
                               "state": {"version": "5.18.1", "revision": aws.PACKAGE_REVISION}}]}
        self.assertEqual(aws.validate_package_resolved(document)["revision"], aws.PACKAGE_REVISION)
        document["pins"][0]["state"]["revision"] = "0" * 40
        with self.assertRaises(aws.QualificationError):
            aws.validate_package_resolved(document)

    def test_checkout_rejects_plugin_before_privacy_check(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Package.swift").write_text(".plugin(name: \"bad\")")
            with self.assertRaises(aws.QualificationError):
                aws.validate_swiftpm_checkout(root, lambda _root, args: aws.PACKAGE_REVISION if args[0] == "rev-parse" else "")

    def test_built_privacy_resource_requires_reviewed_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "PrivacyInfo.xcprivacy"
            path.write_text("wrong")
            with self.assertRaises(aws.QualificationError):
                aws.validate_built_privacy_resource(Path(temporary))

    def test_redaction_removes_private_roots_usernames_and_url_credentials(self):
        private = Path("/tmp/private-root")
        result = aws.redact({"value": "https://user:secret@example.com /Users/alex/file /tmp/private-root/source"}, [private])
        text = json.dumps(result)
        self.assertNotIn("secret", text)
        self.assertNotIn("alex", text)
        self.assertNotIn("private-root", text)

    def test_report_redaction_removes_runner_temp_and_binary_sibling_paths(self):
        value = {"argv": ["/runner/temp/runtime/pkglift", "/runner/temp/output/source"]}
        text = json.dumps(aws.redact(value, [Path("/runner/temp"), Path("/runner/temp/runtime")]))
        self.assertNotIn("/runner/temp", text)
        self.assertNotIn("runtime", text)


if __name__ == "__main__":
    unittest.main()
