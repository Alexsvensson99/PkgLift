import importlib.util
import json
import os
import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/run-real-project-zb.py"
SPEC = importlib.util.spec_from_file_location("real_project_zb", SCRIPT)
zb = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(zb)


def package():
    return {"repositoryURL": zb.PACKAGE_URL, "products": ["SDWebImage"],
            "versionRequirement": {"exact": {"_0": "5.8.4"}}, "confidence": "verified",
            "supportedConsumerLanguages": ["objectiveC"], "supportedConsumerPlatforms": None}


def analysis_plan(root=Path("/tmp/source")):
    analysis = {"project": {"projectPath": str(root / zb.PROJECT), "workspacePath": str(root / zb.WORKSPACE)},
        "candidates": [
            {"pod": {"name": "AFNetworking", "version": "4.0.1", "isDirect": True}, "classification": "review"},
            {"pod": {"name": "SDWebImage", "version": "5.8.4", "isDirect": True}, "classification": "auto", "packageCandidate": package()}]}
    actions = [{"removePod": {"name": "SDWebImage"}},
               {"addSwiftPackage": {"repositoryURL": zb.PACKAGE_URL, "requirement": {"exact": {"_0": "5.8.4"}}}},
               {"linkProduct": {"repositoryURL": zb.PACKAGE_URL, "productName": "SDWebImage", "targetName": zb.TARGET}}]
    plan = {"schemaVersion": 2, "projectPath": str(root / zb.PROJECT), "entries": [
        {"podName": "AFNetworking", "currentVersion": "4.0.1", "classification": "review", "actions": [{"manual": {"description": "retain"}}]},
        {"podName": "SDWebImage", "currentVersion": "5.8.4", "classification": "auto", "targetName": zb.TARGET,
         "packageCandidate": package(), "actions": actions}]}
    return analysis, plan


class LockTests(unittest.TestCase):
    LOCK = """PODS:
  - AFNetworking (4.0.1)
  - SDWebImage (5.8.4):
    - SDWebImage/Core (= 5.8.4)
  - SDWebImage/Core (5.8.4)

DEPENDENCIES:
  - AFNetworking
  - SDWebImage

SPEC CHECKSUMS:
  AFNetworking: 7864c38297c79aaca1500c33288e429c3451fdce
  SDWebImage: cf6922231e95550934da2ada0f20f2becf2ceba9
"""

    def test_accepts_exact_lock_and_rejects_checksum_drift(self):
        self.assertEqual(set(zb.validate_lock(self.LOCK, set(zb.POD_VERSIONS))["roots"]), set(zb.POD_VERSIONS))
        with self.assertRaises(zb.QualificationError):
            zb.validate_lock(self.LOCK.replace("7864c3", "0864c3"), set(zb.POD_VERSIONS))

    def test_final_lock_must_remove_every_sdwebimage_entry(self):
        final = self.LOCK.replace("  - SDWebImage (5.8.4):\n    - SDWebImage/Core (= 5.8.4)\n  - SDWebImage/Core (5.8.4)\n", "")
        final = final.replace("  - SDWebImage\n", "").replace("  SDWebImage: cf6922231e95550934da2ada0f20f2becf2ceba9\n", "")
        zb.validate_lock(final, {"AFNetworking"})


class PodspecTests(unittest.TestCase):
    def spec(self, name):
        source = zb.PODSPEC_INPUTS[name]
        return {"name": name, "version": source["version"], "source": {"git": source["git"], "tag": source["tag"]}}

    def test_rejects_unreviewed_script_even_with_patched_digest(self):
        value = self.spec("AFNetworking"); value["prepare_command"] = "echo bad"
        raw = json.dumps(value, separators=(",", ":")).encode()
        old = zb.PODSPEC_INPUTS["AFNetworking"]["rawSHA256"]
        try:
            zb.PODSPEC_INPUTS["AFNetworking"]["rawSHA256"] = zb.sha256_bytes(raw)
            with self.assertRaises(zb.QualificationError): zb.validate_podspec("AFNetworking", raw)
        finally:
            zb.PODSPEC_INPUTS["AFNetworking"]["rawSHA256"] = old

    def test_tag_binding_accepts_an_annotated_peeled_commit(self):
        output = "1" * 40 + "\trefs/tags/5.8.4\n" + zb.PACKAGE_REVISION + "\trefs/tags/5.8.4^{}\n"
        zb.validate_tag_binding(output, "5.8.4", zb.PACKAGE_REVISION)
        with self.assertRaises(zb.QualificationError):
            zb.validate_tag_binding(output, "5.8.4", "0" * 40)


class IntakeTests(unittest.TestCase):
    def test_repository_intake_matches_runner_contract(self):
        self.assertEqual(zb.validate_execution_intake()["sha256"], zb.INTAKE_SHA256)

    def test_missing_or_wrong_specs_metadata_binding_is_rejected(self):
        intake = json.loads(zb.INTAKE.read_text())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "intake.json"
            for mutation in ("missing", "wrong"):
                with self.subTest(mutation=mutation):
                    value = json.loads(json.dumps(intake))
                    if mutation == "missing":
                        del value["specs"]["metadata"]
                    else:
                        value["specs"]["metadata"]["rawSHA256"] = "0" * 64
                    raw = json.dumps(value, indent=2).encode()
                    path.write_bytes(raw)
                    with patch.object(zb, "INTAKE", path), patch.object(zb, "INTAKE_SHA256", zb.sha256_bytes(raw)):
                        with self.assertRaises(zb.QualificationError) as error:
                            zb.validate_execution_intake()
                    self.assertEqual(error.exception.outcome, "blocked-input")

    def test_missing_or_wrong_retained_af_lock_mode_policy_is_rejected(self):
        intake = json.loads(zb.INTAKE.read_text())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "intake.json"
            for mutation in ("missing", "wrong"):
                with self.subTest(mutation=mutation):
                    value = json.loads(json.dumps(intake))
                    if mutation == "missing":
                        del value["implementationReview"]["retainedAFLockModePolicy"]
                    else:
                        value["implementationReview"]["retainedAFLockModePolicy"]["removeModeBits"] = 0
                    raw = json.dumps(value, indent=2).encode()
                    path.write_bytes(raw)
                    with patch.object(zb, "INTAKE", path), patch.object(zb, "INTAKE_SHA256", zb.sha256_bytes(raw)):
                        with self.assertRaises(zb.QualificationError) as error:
                            zb.validate_execution_intake()
                    self.assertEqual(error.exception.outcome, "blocked-input")


class SpecsCacheTests(unittest.TestCase):
    def runner(self, directory):
        runner = zb.Runner({"binary": Path(directory) / "pkglift", "output": Path(directory) / "output",
                            "runnerTemp": Path(directory)}, 2)
        runner.execute = Mock(return_value="")
        return runner

    def test_rejects_changed_metadata_before_cache_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(directory)
            with patch.object(zb, "SPECS_METADATA_BYTES", b"changed metadata\n"):
                with self.assertRaises(zb.QualificationError) as error:
                    runner.seed_specs_cache()
            self.assertEqual(error.exception.outcome, "blocked-input")
            runner.execute.assert_not_called()

    def test_seeds_exact_metadata_and_original_podspec_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(directory)
            original = {name: ("original " + name).encode() for name in zb.PODSPEC_INPUTS}
            runner.spec_bytes = original.copy()
            result = runner.seed_specs_cache()
            repo = runner.cp_home / "repos" / "pkglift-zb-specs"
            self.assertEqual((repo / zb.SPECS_METADATA_PATH).read_bytes(), zb.SPECS_METADATA_BYTES)
            self.assertEqual(zb.file_sha256(repo / zb.SPECS_METADATA_PATH), zb.SPECS_METADATA_SHA256)
            for name, source in zb.PODSPEC_INPUTS.items():
                self.assertEqual((repo / source["path"]).read_bytes(), original[name])
            self.assertEqual(result["metadata"], zb.validate_specs_metadata())
            runner.execute.assert_any_call("spec-cache-add",
                                           ["git", "-C", repo, "add", "Specs", zb.SPECS_METADATA_PATH])


class RetainedAFLockModeTests(unittest.TestCase):
    def fixture(self, directory):
        root = Path(directory)
        source = root / "reviewed"
        installed = root / "Pods" / "AFNetworking" / "AFNetworking"
        for index in range(14):
            suffix = ".m" if index == 13 else ".h"
            relative = f"AF{index:02d}{suffix}"
            for base in (source, installed):
                path = base / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(f"reviewed-{index}".encode())
            os.chmod(source / relative, 0o755 if index == 13 else 0o644)
            os.chmod(installed / relative, 0o555 if index == 13 else 0o444)
        runner = zb.Runner({"binary": root / "pkglift", "output": root / "output", "runnerTemp": root}, 2)
        runner.reference_payloads["AFNetworking"] = zb.tree_snapshot(source)
        reference = runner.reference_payloads["AFNetworking"]
        expected = json.loads(json.dumps(reference))
        for item in expected.values(): item["mode"] &= ~0o200
        patches = (patch.object(zb, "RETAINED_AF_REVIEWED_SOURCE_TREE_SHA256", zb.tree_digest(reference)),
                   patch.object(zb, "RETAINED_AF_EXPECTED_LOCKED_TREE_SHA256", zb.tree_digest(expected)))
        return runner, root, source, installed, patches

    def test_exact_locked_payload_only_removes_owner_write_and_preserves_baseline(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, root, source, _installed, patches = self.fixture(directory)
            baseline = root / "baseline" / "Pods" / "AFNetworking" / "AFNetworking"
            for path in source.iterdir():
                copied = baseline / path.name; copied.parent.mkdir(parents=True, exist_ok=True)
                copied.write_bytes(path.read_bytes()); os.chmod(copied, path.stat().st_mode & 0o777)
            with patches[0], patches[1]:
                baseline_payload = runner.validate_pod_payload(root / "baseline", {"AFNetworking"})["AFNetworking"]
                with self.assertRaises(zb.QualificationError):
                    runner.validate_pod_payload(root, {"AFNetworking"})
                locked = runner.validate_retained_af_locked_payload(root)
            self.assertEqual(baseline_payload["selectedSourceTreeSHA256"], locked["reviewedSourceTreeSHA256"])
            self.assertEqual(locked["selectedSourceEntries"], 14)
            self.assertEqual(locked["modeTransitions"], {"0644->0444": 13, "0755->0555": 1})

    def test_rejects_every_descriptor_change_after_locking(self):
        mode_mutations = {"mode-executable": 0o445, "mode-group": 0o464,
                          "mode-other": 0o440, "mode-owner-write": 0o644}
        for mutation in ("bytes", "size", "path", "kind", *mode_mutations, "add", "remove"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                runner, root, _source, installed, patches = self.fixture(directory)
                target = installed / "AF00.h"
                if mutation in {"bytes", "size"}: os.chmod(target, 0o644)
                if mutation == "bytes":
                    self.assertEqual(len(target.read_bytes()), len(b"changed-00"))
                    target.write_bytes(b"changed-00"); os.chmod(target, 0o444)
                elif mutation == "size":
                    target.write_bytes(target.read_bytes() + b"x"); os.chmod(target, 0o444)
                elif mutation == "path": target.rename(installed / "renamed.h")
                elif mutation == "kind": target.unlink(); target.mkdir()
                elif mutation in mode_mutations: os.chmod(target, mode_mutations[mutation])
                elif mutation == "add": (installed / "extra.h").write_bytes(b"extra")
                else: target.unlink()
                with patches[0], patches[1]:
                    with self.assertRaises(zb.QualificationError):
                        runner.validate_retained_af_locked_payload(root)

    def test_rejects_a_changed_reference_tree_against_the_pinned_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, root, _source, _installed, patches = self.fixture(directory)
            with patches[0], patches[1]:
                runner.validate_retained_af_locked_payload(root)
                runner.reference_payloads["AFNetworking"]["AF00.h"]["sha256"] = "0" * 64
                with self.assertRaises(zb.QualificationError):
                    runner.validate_retained_af_locked_payload(root)

    def test_rejects_payload_root_and_ancestor_symlinks_without_writing_outside(self):
        for relative in ("Pods", "Pods/AFNetworking", "Pods/AFNetworking/AFNetworking"):
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as directory:
                runner, root, _source, _installed, patches = self.fixture(directory)
                target = root / relative
                outside = root / "outside"
                target.rename(outside)
                target.symlink_to(outside, target_is_directory=True)
                before = zb.tree_snapshot(outside)
                with patches[0], patches[1]:
                    with self.assertRaises(zb.QualificationError):
                        runner.validate_retained_af_locked_payload(root)
                self.assertEqual(zb.tree_snapshot(outside), before)


class PackageResolutionInputTests(unittest.TestCase):
    def fixture(self, directory):
        root = Path(directory) / "source"; root.mkdir()
        (root / ".git/info").mkdir(parents=True)
        for relative in zb.PACKAGE_RESOLVED_PATHS:
            (root / relative).parent.mkdir(parents=True)
        runner = zb.Runner({"binary": root / "pkglift", "output": root / "output", "runnerTemp": Path(directory)}, 2)
        status_calls = 0
        def git(path, args):
            nonlocal status_calls
            if args[:2] == ["rev-parse", "HEAD"]: return zb.PACKAGE_REVISION
            if args[0] == "status" and path == root:
                status_calls += 1
                return "" if status_calls == 1 else "?? " + zb.PACKAGE_RESOLVED_PATHS[0] + "\0"
            return ""
        runner.git = Mock(side_effect=git)
        return runner, root

    def checkout(self, root):
        checkout = root / "derived/SourcePackages/checkouts/SDWebImage"
        checkout.mkdir(parents=True); (checkout / "Package.swift").write_bytes(b"reviewed manifest")
        return checkout

    def test_prepares_only_the_two_exact_excluded_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, root = self.fixture(directory)
            result = runner.prepare_package_resolution_inputs(root)
            self.assertEqual(result["paths"], list(zb.PACKAGE_RESOLVED_PATHS))
            self.assertEqual(result["expectedStatusAdded"], "?? " + zb.PACKAGE_RESOLVED_PATHS[0])
            for relative in zb.PACKAGE_RESOLVED_PATHS:
                path = root / relative
                self.assertEqual(path.read_bytes(), zb.PACKAGE_RESOLVED_BYTES)
                self.assertEqual(path.stat().st_mode & 0o777, 0o644)
            self.assertEqual(runner.git.call_count, 4)

    def test_rejects_existing_second_input_and_symlinked_parent_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, root = self.fixture(directory)
            second = root / zb.PACKAGE_RESOLVED_PATHS[1]; second.write_bytes(b"existing")
            with self.assertRaises(zb.QualificationError): runner.prepare_package_resolution_inputs(root)
            self.assertFalse((root / zb.PACKAGE_RESOLVED_PATHS[0]).exists())
        with tempfile.TemporaryDirectory() as directory:
            runner, root = self.fixture(directory)
            parent = (root / zb.PACKAGE_RESOLVED_PATHS[0]).parent
            outside = root / "outside"; parent.rename(outside); parent.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(zb.QualificationError): runner.prepare_package_resolution_inputs(root)

    def test_context_rejects_missing_extra_size_mode_and_malformed_pins(self):
        for mutation in ("missing", "extra", "pods-extra", "size", "mode", "pins"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                runner, root = self.fixture(directory); runner.prepare_package_resolution_inputs(root)
                checkout = self.checkout(root)
                with patch.object(zb, "PACKAGE_MANIFEST_SHA256", zb.file_sha256(checkout / "Package.swift")):
                    if mutation == "missing": (root / zb.PACKAGE_RESOLVED_PATHS[0]).unlink()
                    elif mutation in {"extra", "pods-extra"}:
                        extra = root / ("unexpected/Package.resolved" if mutation == "extra" else "Pods/Unexpected/Package.resolved")
                        extra.parent.mkdir(parents=True); extra.write_bytes(zb.PACKAGE_RESOLVED_BYTES)
                    elif mutation == "size": (root / zb.PACKAGE_RESOLVED_PATHS[0]).write_bytes(zb.PACKAGE_RESOLVED_BYTES + b"x")
                    elif mutation == "mode": os.chmod(root / zb.PACKAGE_RESOLVED_PATHS[0], 0o600)
                    else: (root / zb.PACKAGE_RESOLVED_PATHS[0]).write_bytes(b'{"pins": []}\n')
                    with self.assertRaises(zb.QualificationError): runner.validate_package_resolution_context(root, root / "derived")

    def test_final_settings_require_context_and_lock_flags_for_app_probes(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, root = self.fixture(directory); runner.prepare_package_resolution_inputs(root)
            checkout = self.checkout(root)
            runner.execute = Mock(side_effect=lambda _label, command, **_kwargs: [{"target": command[command.index("-target") + 1], "buildSettings": {"IPHONEOS_DEPLOYMENT_TARGET": "15.0"}}])
            with patch.object(zb, "PACKAGE_MANIFEST_SHA256", zb.file_sha256(checkout / "Package.swift")):
                with self.assertRaises(zb.QualificationError): runner.settings(root, "final", {"AFNetworking"})
                runner.settings(root, "final", {"AFNetworking"}, {"derived": str(root / "derived")})
            app_calls = [call.args[1] for call in runner.execute.call_args_list if "-project" in call.args[1] and root / zb.PROJECT in call.args[1]]
            self.assertTrue(app_calls)
            for command in app_calls:
                for flag in ("-onlyUsePackageVersionsFromResolvedFile", "-disableAutomaticPackageResolution", "-skipPackageUpdates", "-clonedSourcePackagesDirPath"):
                    self.assertIn(flag, command)
                self.assertNotIn("-derivedDataPath", command)

    def test_resolver_rewrite_overrides_a_command_failure_with_safety_error(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, root = self.fixture(directory); runner.prepare_package_resolution_inputs(root)
            checkout = self.checkout(root)
            def rewrite_then_fail(_label, _command, **_kwargs):
                (root / zb.PACKAGE_RESOLVED_PATHS[1]).write_bytes(b"rewritten")
                raise zb.QualificationError("failed-migration", "resolver failed")
            runner.execute = Mock(side_effect=rewrite_then_fail)
            with patch.object(zb, "PACKAGE_MANIFEST_SHA256", zb.file_sha256(checkout / "Package.swift")):
                with self.assertRaises(zb.QualificationError) as error:
                    runner.resolve_reviewed_package(root, root / "derived")
            self.assertEqual(error.exception.outcome, "failed-safety")

    def test_unchanged_resolver_failure_with_empty_derived_preserves_command_outcome(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, root = self.fixture(directory); runner.prepare_package_resolution_inputs(root)
            (root / "derived/SourcePackages").mkdir(parents=True)
            runner.execute = Mock(side_effect=zb.QualificationError("failed-migration", "resolver failed"))
            with self.assertRaises(zb.QualificationError) as error:
                runner.resolve_reviewed_package(root, root / "derived")
            self.assertEqual(error.exception.outcome, "failed-migration")

    def test_resolver_unexpected_swiftpm_write_is_failed_safety(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, root = self.fixture(directory); runner.prepare_package_resolution_inputs(root)
            def mutate(_label, _command, **_kwargs):
                (root / zb.PACKAGE_RESOLVED_PATHS[0]).parent.joinpath("unexpected").write_text("bad")
            runner.execute = Mock(side_effect=mutate)
            with self.assertRaises(zb.QualificationError) as error:
                runner.resolve_reviewed_package(root, root / "derived")
            self.assertEqual(error.exception.outcome, "failed-safety")

    def test_final_setting_checkout_mutation_stops_before_second_app_target(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, root = self.fixture(directory); runner.prepare_package_resolution_inputs(root)
            checkout = self.checkout(root); manifest_hash = zb.file_sha256(checkout / "Package.swift")
            calls = []
            def mutate_then_fail(_label, command, **_kwargs):
                calls.append(command)
                (checkout / "Package.swift").write_bytes(b"mutated")
                raise zb.QualificationError("failed-migration", "settings failed")
            runner.execute = Mock(side_effect=mutate_then_fail)
            with patch.object(zb, "PACKAGE_MANIFEST_SHA256", manifest_hash):
                with self.assertRaises(zb.QualificationError) as error:
                    runner.settings(root, "final", {"AFNetworking"}, {"derived": str(root / "derived")})
            self.assertEqual(error.exception.outcome, "failed-safety")
            self.assertEqual(len(calls), 1)

    def test_final_build_checkout_mutation_is_detected_in_finally(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, root = self.fixture(directory); runner.prepare_package_resolution_inputs(root)
            checkout = self.checkout(root); manifest_hash = zb.file_sha256(checkout / "Package.swift")
            def mutate_then_fail(_label, _command, **_kwargs):
                (checkout / "Package.swift").write_bytes(b"mutated")
                raise zb.QualificationError("failed-migration", "build failed")
            runner.execute = Mock(side_effect=mutate_then_fail)
            with patch.object(zb, "PACKAGE_MANIFEST_SHA256", manifest_hash):
                with self.assertRaises(zb.QualificationError) as error:
                    runner.build(root, root / "derived", "final-build", "failed-migration", {"derived": str(root / "derived")})
            self.assertEqual(error.exception.outcome, "failed-safety")


class SchemeTests(unittest.TestCase):
    def test_requires_both_test_targets_and_no_execution_actions(self):
        flags = " ".join(f'{key}="{value}"' for key, value in zb.SCHEME_BUILD_FLAGS.items())
        identity = zb.TARGET_IDENTITIES[zb.TARGET]
        raw = f'''<Scheme><BuildAction><BuildActionEntries><BuildActionEntry {flags}><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identity['blueprintID']}" BuildableName="{identity['buildableName']}" BlueprintName="{zb.TARGET}" ReferencedContainer="container:{zb.PROJECT}"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction><Testables><TestableReference><BuildableReference BlueprintName="{zb.SIBLINGS[0]}"/></TestableReference><TestableReference><BuildableReference BlueprintName="{zb.SIBLINGS[1]}"/></TestableReference></Testables></TestAction></Scheme>'''.encode()
        self.assertEqual(zb.validate_scheme_bytes(raw)["tests"], list(zb.SIBLINGS))
        with self.assertRaises(zb.QualificationError):
            zb.validate_scheme_bytes(raw.replace(b"</Scheme>", b"<ExecutionAction/></Scheme>"))
        with self.assertRaises(zb.QualificationError):
            zb.validate_scheme_bytes(raw.replace(f"container:{zb.PROJECT}".encode(), b"container:Other.xcodeproj"))
        with self.assertRaises(zb.QualificationError):
            zb.validate_scheme_bytes(raw.replace(b'buildForArchiving="YES"', b'buildForArchiving="NO"'))


class SchemeDiscoveryTests(unittest.TestCase):
    def runner(self, directory, mutate=False, index_changed=False, dirty=False):
        contract = {"binary": Path(directory) / "pkglift", "output": Path(directory) / "output",
                    "runnerTemp": Path(directory), "artifact": {}}
        runner = zb.Runner(contract, 2)

        def execute(_label, command, **_kwargs):
            if mutate:
                (Path(command[-1]).parent / "generated.txt").write_text("private generated content")
            return {"workspace": {"schemes": [zb.TARGET]}}

        runner.execute = Mock(side_effect=execute)
        runner.git = Mock(side_effect=["original index", "", "changed index" if index_changed else "original index",
                                      "?? private-status-path\0" if dirty else ""])
        return runner, contract

    def test_unchanged_discovery_passes_and_collects_all_postconditions(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, _ = self.runner(directory)
            self.assertEqual(runner.discover_scheme(Path(directory), "probe")["name"], zb.TARGET)
            evidence = runner.scheme_discovery["probe"]
            self.assertEqual(evidence["changedPathCount"], 0)
            self.assertFalse(evidence["treeChanged"] or evidence["indexChanged"] or evidence["gitStatusDirty"])
            self.assertEqual(runner.git.call_count, 4)

    def test_each_mutation_refuses_and_tree_failure_does_not_skip_git_checks(self):
        for tree, index, status in [(True, False, False), (False, True, False),
                                    (False, False, True), (True, True, True)]:
            with self.subTest(tree=tree, index=index, status=status), tempfile.TemporaryDirectory() as directory:
                runner, _ = self.runner(directory, tree, index, status)
                with self.assertRaises(zb.QualificationError) as error:
                    runner.discover_scheme(Path(directory), "probe")
                self.assertEqual(error.exception.outcome, "failed-safety")
                evidence = runner.scheme_discovery["probe"]
                self.assertEqual((evidence["treeChanged"], evidence["indexChanged"], evidence["gitStatusDirty"]),
                                 (tree, index, status))
                self.assertEqual(runner.git.call_count, 4)
                serialized = json.dumps(evidence)
                self.assertNotIn("private generated content", serialized)
                self.assertNotIn("private-status-path", serialized)
                self.assertNotIn("original index", serialized)

    def test_failed_run_writes_diagnostics_before_returning_error(self):
        with tempfile.TemporaryDirectory() as directory, ExitStack() as patches:
            runner, contract = self.runner(directory, mutate=True, index_changed=True, dirty=True)
            for method in ("command_env", "environment_gate", "fetch_inputs", "seed_specs_cache"):
                patches.enter_context(patch.object(runner, method, return_value={}))
            patches.enter_context(patch.object(runner, "clone_source",
                                               side_effect=lambda root, _label: root.mkdir() or {}))
            patches.enter_context(patch.object(runner, "prepare_portable_scheme", return_value={"tree": "same"}))
            setup = patches.enter_context(patch.object(runner, "prepare_swiftpm_directories",
                                                       return_value={"afterTreeSHA256": "same"}))
            original_execute = runner.execute.side_effect

            def execute_after_setup(*args, **kwargs):
                self.assertEqual([call.args[0].name for call in setup.call_args_list],
                                 ["baseline-source", "migration-source"])
                return original_execute(*args, **kwargs)

            runner.execute.side_effect = execute_after_setup
            patches.enter_context(patch.object(zb, "validate_execution_intake", return_value={}))
            original_is_file = Path.is_file
            patches.enter_context(patch.object(Path, "is_file",
                lambda path: str(path) == "/usr/bin/sandbox-exec" or original_is_file(path)))
            with self.assertRaises(zb.QualificationError):
                runner.run(contract)
            summary = json.loads((runner.report / "summary.json").read_text())
            evidence = summary["schemeDiscovery"]["baseline-scheme-list"]
            self.assertEqual(summary["status"], "failed-safety")
            self.assertEqual(evidence["changes"][0]["path"], "generated.txt")
            self.assertTrue(evidence["indexChanged"] and evidence["gitStatusDirty"])
            self.assertNotIn("baselineBuild", summary)
            self.assertEqual(runner.execute.call_count, 1)

    def test_changed_metadata_excludes_link_targets_and_xcode_usernames(self):
        path = "App.xcodeproj/xcuserdata/private-user.xcuserdatad/link"
        before = {path: {"kind": "symlink", "mode": 511, "target": "/private/secret-before"},
                  "removed": {"kind": "file", "mode": 420, "sha256": "a" * 64, "size": 3}}
        after = {path: {"kind": "symlink", "mode": 511, "target": "/private/secret-after"},
                 "added": {"kind": "directory", "mode": 493}}
        result = zb.source_mutation_evidence(before, after, "", "", "")
        self.assertEqual([row["change"] for row in result["changes"]], ["modified", "added", "removed"])
        link = result["changes"][0]
        self.assertEqual(link["after"]["targetSHA256"], zb.sha256_bytes(b"/private/secret-after"))
        self.assertIn("<user>.xcuserdatad", link["path"])
        for secret in ("secret-before", "secret-after", "private-user"):
            self.assertNotIn(secret, json.dumps(result))

    def test_diagnostics_are_bounded_without_truncating_the_mutation_decision(self):
        after = {f"{index:03d}" + "x" * 1100: {"kind": "directory", "mode": 493} for index in range(70)}
        result = zb.source_mutation_evidence({}, after, "", "", "")
        self.assertTrue(result["treeChanged"] and result["changesTruncated"])
        self.assertEqual(result["changedPathCount"], 70)
        self.assertEqual(len(result["changes"]), 64)
        self.assertTrue(all(row["pathTruncated"] and len(row["path"]) == 1024 for row in result["changes"]))
        self.assertEqual(result["afterTreeSHA256"], zb.tree_digest(after))


class SwiftPMDirectorySetupTests(unittest.TestCase):
    def parents(self, root):
        for workspace in (zb.WORKSPACE, f"{zb.PROJECT}/project.xcworkspace"):
            (root / workspace / "xcshareddata").mkdir(parents=True)

    def runner(self, root):
        runner = zb.Runner({"binary": root / "pkglift", "output": root / "output", "runnerTemp": root}, 2)
        runner.git = Mock(side_effect=["index", "", "index", ""])
        return runner

    def test_mismatched_copy_setup_stops_before_discovery(self):
        with tempfile.TemporaryDirectory() as directory, ExitStack() as patches:
            root = Path(directory); runner = self.runner(root)
            contract = {"artifact": {}}
            for method in ("command_env", "environment_gate", "fetch_inputs", "seed_specs_cache", "clone_source"):
                patches.enter_context(patch.object(runner, method, return_value={}))
            patches.enter_context(patch.object(runner, "prepare_portable_scheme", return_value={"tree": "same"}))
            patches.enter_context(patch.object(runner, "prepare_swiftpm_directories", side_effect=[
                {"afterTreeSHA256": "same", "beforeTreeSHA256": "one"},
                {"afterTreeSHA256": "same", "beforeTreeSHA256": "different"}]))
            discover = patches.enter_context(patch.object(runner, "discover_scheme"))
            patches.enter_context(patch.object(zb, "validate_execution_intake", return_value={}))
            original_is_file = Path.is_file
            patches.enter_context(patch.object(Path, "is_file",
                lambda path: str(path) == "/usr/bin/sandbox-exec" or original_is_file(path)))
            with self.assertRaises(zb.QualificationError) as error: runner.run(contract)
            self.assertEqual(error.exception.outcome, "failed-safety")
            discover.assert_not_called()

    def test_exact_setup_in_both_copies_is_identical_despite_restrictive_umask(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshots = []
            for name, mask in [("baseline", 0o077), ("migration", 0o022)]:
                root = Path(directory) / name
                self.parents(root)
                before = zb.tree_snapshot(root)
                runner = self.runner(root)
                old = os.umask(mask)
                try:
                    result = runner.prepare_swiftpm_directories(root)
                finally:
                    os.umask(old)
                after = zb.tree_snapshot(root)
                self.assertEqual(zb.changed_paths(before, after), list(zb.SWIFTPM_SETUP_DIRECTORIES))
                self.assertTrue(result["noFilesCreated"] and result["indexUnchanged"] and result["worktreeClean"])
                for leaf in (path for path in zb.SWIFTPM_SETUP_DIRECTORIES if path.endswith("/configuration")):
                    self.assertEqual(list((root / leaf).iterdir()), [])
                for path in zb.SWIFTPM_SETUP_DIRECTORIES:
                    self.assertEqual(after[path], {"kind": "directory", "mode": 0o777})
                    if path.endswith("/swiftpm"):
                        self.assertEqual([child.name for child in (root / path).iterdir()], ["configuration"])
                snapshots.append(result)
            self.assertEqual(snapshots[0], snapshots[1])

    def test_rejects_any_existing_setup_path_without_modifying_it(self):
        for relative in zb.SWIFTPM_SETUP_DIRECTORIES:
            for kind in ("empty-directory", "nonempty-directory", "file", "symlink"):
                with self.subTest(path=relative, kind=kind), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory); self.parents(root)
                    path = root / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    if kind.endswith("directory"):
                        path.mkdir()
                        if kind == "nonempty-directory": (path / "keep").write_text("keep")
                    elif kind == "file": path.write_text("keep")
                    else: path.symlink_to("missing")
                    before = zb.tree_snapshot(root)
                    runner = self.runner(root)
                    with self.assertRaises(zb.QualificationError): runner.prepare_swiftpm_directories(root)
                    self.assertEqual(zb.tree_snapshot(root), before)
                    runner.git.assert_not_called()

    def test_rejects_every_symlinked_ancestor_without_writing_outside_copy(self):
        ancestors = [zb.WORKSPACE, f"{zb.WORKSPACE}/xcshareddata", zb.PROJECT,
                     f"{zb.PROJECT}/project.xcworkspace",
                     f"{zb.PROJECT}/project.xcworkspace/xcshareddata"]
        for ancestor in ancestors:
            with self.subTest(ancestor=ancestor), tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / "source"; self.parents(root)
                outside = Path(directory) / "outside"
                original = root / ancestor
                original.rename(outside)
                original.symlink_to(outside, target_is_directory=True)
                before = zb.tree_snapshot(Path(directory))
                runner = self.runner(root)
                with self.assertRaises(zb.QualificationError): runner.prepare_swiftpm_directories(root)
                self.assertEqual(zb.tree_snapshot(Path(directory)), before)
                runner.git.assert_not_called()

    def test_rejects_missing_app_workspace_before_creating_outer_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / zb.WORKSPACE / "xcshareddata").mkdir(parents=True)
            before = zb.tree_snapshot(root); runner = self.runner(root)
            with self.assertRaises(zb.QualificationError): runner.prepare_swiftpm_directories(root)
            self.assertEqual(zb.tree_snapshot(root), before)
            runner.git.assert_not_called()

    def test_rejects_git_mutation_during_preparation(self):
        for index_after, status_after in [("changed-index", ""), ("index", "?? extra\0")]:
            with self.subTest(index=index_after, status=status_after), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); self.parents(root); runner = self.runner(root)
                runner.git = Mock(side_effect=["index", "", index_after, status_after])
                with self.assertRaises(zb.QualificationError) as error: runner.prepare_swiftpm_directories(root)
                self.assertEqual(error.exception.outcome, "failed-safety")

    def test_rejects_unexpected_extra_file_during_setup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); self.parents(root)
            original = Path.mkdir

            def mkdir(path, *args, **kwargs):
                original(path, *args, **kwargs)
                if path.name == "configuration": (path / "unexpected").write_text("extra")

            with patch.object(Path, "mkdir", mkdir), self.assertRaises(zb.QualificationError) as error:
                self.runner(root).prepare_swiftpm_directories(root)
            self.assertEqual(error.exception.outcome, "failed-safety")

    def test_discovery_still_rejects_file_created_inside_prepared_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); self.parents(root)
            runner = self.runner(root); runner.prepare_swiftpm_directories(root)
            runner.git = Mock(side_effect=["index", "", "index", "?? extra\0"])

            def execute(*_args, **_kwargs):
                (root / zb.SWIFTPM_SETUP_DIRECTORIES[-1] / "extra").write_text("not allowed")
                return {"workspace": {"schemes": [zb.TARGET]}}

            runner.execute = Mock(side_effect=execute)
            with self.assertRaises(zb.QualificationError) as error:
                runner.discover_scheme(root, "probe")
            self.assertEqual(error.exception.outcome, "failed-safety")
            self.assertEqual(runner.scheme_discovery["probe"]["changedPathCount"], 1)


class PlanTests(unittest.TestCase):
    def test_accepts_only_sd_auto_for_objc_app(self):
        analysis, plan = analysis_plan()
        self.assertEqual(zb.validate_analysis_and_plan(analysis, plan, Path("/tmp/source"))["auto"], ["SDWebImage"])

    def test_rejects_registry_source_plan_without_schema_boundary(self):
        for schema in (None, 1, 3):
            analysis, plan = analysis_plan()
            plan["schemaVersion"] = schema
            with self.assertRaises(zb.QualificationError):
                zb.validate_analysis_and_plan(analysis, plan, Path("/tmp/source"))

    def test_rejects_af_auto_or_sibling_link(self):
        analysis, plan = analysis_plan(); analysis["candidates"][0]["classification"] = "auto"
        with self.assertRaises(zb.QualificationError): zb.validate_analysis_and_plan(analysis, plan, Path("/tmp/source"))
        analysis, plan = analysis_plan(); plan["entries"][1]["actions"][2]["linkProduct"]["targetName"] = zb.SIBLINGS[0]
        with self.assertRaises(zb.QualificationError): zb.validate_analysis_and_plan(analysis, plan, Path("/tmp/source"))


class ProjectTests(unittest.TestCase):
    def project(self, include_package=True):
        objects = {"P": {"isa": "PBXProject", "targets": [], "attributes": {"LastUpgradeCheck": "0730"}},
                   "BF": {"isa": "PBXBuildFile", "fileRef": "FR", "settings": {"ATTRIBUTES": ["Weak"]}},
                   "FR": {"isa": "PBXFileReference", "path": "StoreKit.framework", "sourceTree": "SDKROOT"}}
        for index, name in enumerate((zb.TARGET, *zb.SIBLINGS)):
            target, phase = f"T{index}", f"F{index}"
            phases = [phase] + (["S"] if name == zb.TARGET else [])
            dependencies = []
            if name in zb.SIBLINGS:
                dependency, proxy = f"TD{index}", f"PX{index}"
                dependencies = [dependency]
                objects[dependency] = {"isa": "PBXTargetDependency", "target": "T0", "targetProxy": proxy}
                objects[proxy] = {"isa": "PBXContainerItemProxy", "containerPortal": "P", "proxyType": "1",
                                  "remoteGlobalIDString": "T0", "remoteInfo": zb.TARGET}
            objects[target] = {"isa": "PBXNativeTarget", "name": name, "productType": zb.TARGET_IDENTITIES[name]["productType"],
                               "buildPhases": phases, "buildRules": [], "dependencies": dependencies,
                               "buildConfigurationList": f"L{index}"}
            objects[phase] = {"isa": "PBXFrameworksBuildPhase", "files": ["BF"] if name == zb.TARGET else [],
                              "buildActionMask": "2147483647", "runOnlyForDeploymentPostprocessing": "0"}
            objects[f"L{index}"] = {"isa": "XCConfigurationList", "buildConfigurations": [f"C{index}"]}
            objects[f"C{index}"] = {"isa": "XCBuildConfiguration", "buildSettings": {"X": "Y"}}
            objects["P"]["targets"].append(target)
        objects["S"] = {"isa": "PBXShellScriptBuildPhase", "name": "[CP] Check Pods Manifest.lock",
                        "shellPath": "/bin/sh", "shellScript": "expected",
                        "inputPaths": ["${PODS_PODFILE_DIR_PATH}/Podfile.lock", "${PODS_ROOT}/Manifest.lock"],
                        "outputPaths": ["$(DERIVED_FILE_DIR)/Pods-ZBNetworkingDemo-checkManifestLockResult.txt"]}
        if include_package:
            objects["P"]["packageReferences"] = ["R"]
            objects["R"] = {"isa": "XCRemoteSwiftPackageReference", "repositoryURL": zb.PACKAGE_URL,
                              "requirement": {"kind": "exactVersion", "version": "5.8.4"}}
            objects["D"] = {"isa": "XCSwiftPackageProductDependency", "package": "R", "productName": "SDWebImage"}
            objects["B"] = {"isa": "PBXBuildFile", "productRef": "D"}
            objects["F0"]["files"].append("B")
        return {"classes": {}, "archiveVersion": "1", "objectVersion": "56", "rootObject": "P", "objects": objects}

    def pods_project(self, names=("Pods-ZBNetworkingDemo", "AFNetworking", "SDWebImage")):
        objects = {"PP": {"isa": "PBXProject", "targets": []}}
        for index, name in enumerate(names):
            target = f"PT{index}"
            objects[target] = {"isa": "PBXNativeTarget", "name": name, "buildPhases": [],
                               "buildRules": [], "dependencies": []}
            objects["PP"]["targets"].append(target)
        return {"rootObject": "PP", "objects": objects}

    def test_package_links_once_to_app_and_zero_to_siblings(self):
        self.assertEqual(zb.validate_linkage(self.project()), {zb.TARGET: 1, zb.SIBLINGS[0]: 0, zb.SIBLINGS[1]: 0})

    def test_sibling_closure_detects_configuration_change(self):
        first = self.project(); second = json.loads(json.dumps(first)); second["objects"]["C1"]["buildSettings"]["X"] = "changed"
        self.assertNotEqual(zb.sibling_closure(first), zb.sibling_closure(second))

    def test_execution_input_validator_rejects_pods_shell_phase(self):
        project = self.project()
        pods = self.pods_project()
        old = zb.MANIFEST_PHASE_SHA256
        try:
            zb.MANIFEST_PHASE_SHA256 = zb.sha256_bytes(b"expected")
            self.assertEqual(zb.validate_build_execution_inputs(
                project, pods, {"Pods-ZBNetworkingDemo", "AFNetworking", "SDWebImage"})["podsShellPhaseCount"], 0)
            pods["objects"]["PS"] = {"isa": "PBXShellScriptBuildPhase"}
            with self.assertRaises(zb.QualificationError):
                zb.validate_build_execution_inputs(
                    project, pods, {"Pods-ZBNetworkingDemo", "AFNetworking", "SDWebImage"})
        finally:
            zb.MANIFEST_PHASE_SHA256 = old

    def test_execution_input_validator_rejects_build_rules_and_non_native_targets(self):
        mutations = [("app build rule", "app", "PBXBuildRule"),
                     ("Pods build rule", "pods", "PBXBuildRule"),
                     ("app legacy target", "app", "PBXLegacyTarget"),
                     ("Pods aggregate target", "pods", "PBXAggregateTarget"),
                     ("unknown execution target", "app", "PBXCustomTarget")]
        for label, location, isa in mutations:
            with self.subTest(label=label):
                project, pods = self.project(), self.pods_project()
                (project if location == "app" else pods)["objects"]["M"] = {"isa": isa}
                with self.assertRaises(zb.QualificationError):
                    zb.validate_build_execution_inputs(
                        project, pods, {"Pods-ZBNetworkingDemo", "AFNetworking", "SDWebImage"})

    def test_zb_protected_state_allows_only_exact_reviewed_package_graph(self):
        baseline, migrated = self.project(include_package=False), self.project(include_package=True)
        self.assertEqual(zb.zb_protected_project_state(baseline), zb.zb_protected_project_state(migrated))
        migrated["objects"]["B2"] = {"isa": "PBXBuildFile", "productRef": "D"}
        with self.assertRaises(zb.QualificationError):
            zb.zb_protected_project_state(migrated)

    def test_zb_protected_state_detects_framework_phase_and_dependency_proxy_mutations(self):
        baseline = self.project(include_package=False)
        expected = zb.zb_protected_project_state(baseline)
        framework_changed = json.loads(json.dumps(baseline))
        framework_changed["objects"]["F0"]["runOnlyForDeploymentPostprocessing"] = "1"
        self.assertNotEqual(expected, zb.zb_protected_project_state(framework_changed))
        proxy_changed = json.loads(json.dumps(baseline))
        proxy_changed["objects"]["PX1"]["remoteInfo"] = "different"
        self.assertNotEqual(expected, zb.zb_protected_project_state(proxy_changed))
        phases_changed = json.loads(json.dumps(baseline))
        phases_changed["objects"]["T0"]["buildPhases"].reverse()
        self.assertNotEqual(expected, zb.zb_protected_project_state(phases_changed))
        root_changed = json.loads(json.dumps(baseline))
        root_changed["objects"]["P"]["attributes"]["LastUpgradeCheck"] = "9999"
        self.assertNotEqual(expected, zb.zb_protected_project_state(root_changed))


class XcodeProbeMutationTests(unittest.TestCase):
    def runner(self, directory, mutation=None, dirty=False, fail=False):
        root = Path(directory) / "source"; root.mkdir()
        derived = Path(directory) / "derived"
        runner = zb.Runner({"binary": root / "pkglift", "output": Path(directory) / "report-output",
                            "runnerTemp": Path(directory)}, 2)
        state = {"ran": False}
        status_before = " M reviewed-migration-change\0" if dirty else ""

        def git(_root, args, **_kwargs):
            if args[0] == "ls-files":
                return "different index" if state["ran"] and mutation == "index" else "index"
            self.assertEqual(args[0], "status")
            return status_before + ("?? new-private-status\0" if state["ran"] and mutation == "status" else "")

        def execute(_label, command, **_kwargs):
            state["ran"] = True
            if mutation == "tree": (root / "unexpected").write_text("private source bytes")
            if fail: raise zb.QualificationError("inconclusive-baseline", "probe failed")
            if "-showBuildSettings" in command:
                target = command[command.index("-target") + 1]
                return [{"target": target, "buildSettings": {"IPHONEOS_DEPLOYMENT_TARGET": "15.0"}}]
            if "-list" in command: return {"workspace": {"schemes": [zb.TARGET]}}
            for name in ("ZBNetworkingDemo.app", "ZBNetworkingDemoTests.xctest", "ZBNetworkingDemoUITests.xctest"):
                (derived / name).mkdir(parents=True, exist_ok=True)
            return ""

        runner.git = Mock(side_effect=git); runner.execute = Mock(side_effect=execute)
        return runner, root, derived

    def prepare_run(self, runner, patches):
        for method in ("command_env", "environment_gate", "fetch_inputs", "seed_specs_cache", "discover_scheme",
                       "validate_pod_payload", "pbx_json"):
            patches.enter_context(patch.object(runner, method, return_value={}))
        patches.enter_context(patch.object(runner, "clone_source", side_effect=lambda path, _label: path.mkdir() or {}))
        patches.enter_context(patch.object(runner, "prepare_portable_scheme", return_value={"tree": "same"}))
        patches.enter_context(patch.object(runner, "prepare_swiftpm_directories", return_value={"afterTreeSHA256": zb.tree_digest({})}))
        build = patches.enter_context(patch.object(runner, "build"))
        for function in ("validate_execution_intake", "validate_build_execution_inputs", "validate_header_links",
                         "sibling_closure", "zb_protected_project_state"):
            patches.enter_context(patch.object(zb, function, return_value={}))
        patches.enter_context(patch.object(zb.shared, "protected_project_state", return_value={}))
        original_is_file = Path.is_file
        patches.enter_context(patch.object(Path, "is_file",
            lambda path: str(path) == "/usr/bin/sandbox-exec" or original_is_file(path)))
        return build

    def test_settings_accept_unchanged_reviewed_dirty_state_and_observe_every_target(self):
        with tempfile.TemporaryDirectory() as directory:
            runner, root, _ = self.runner(directory, dirty=True)
            result = runner.settings(root, "baseline", {"AFNetworking"})
            self.assertEqual(set(result), {zb.TARGET, *zb.SIBLINGS, "AFNetworking"})
            self.assertEqual(runner.execute.call_count, 4)
            self.assertEqual(len(runner.source_mutation_checks), 5)
            self.assertTrue(all(not e["statusChanged"] and not e["treeChanged"] and not e["indexChanged"]
                                and e["gitStatusDirty"] for e in runner.source_mutation_checks.values()))

    def test_each_settings_mutation_stops_before_the_next_command(self):
        for mutation in ("tree", "index", "status"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                runner, root, _ = self.runner(directory, mutation=mutation)
                with self.assertRaises(zb.QualificationError) as error: runner.settings(root, "baseline", {"AFNetworking"})
                self.assertEqual(error.exception.outcome, "failed-safety")
                self.assertEqual(runner.execute.call_count, 1)
                self.assertEqual(len(runner.source_mutation_checks), 2)  # Individual probe and aggregate.
                for evidence in runner.source_mutation_checks.values(): self.assertTrue(evidence[mutation + "Changed"])
                self.assertNotIn("private source bytes", json.dumps(runner.source_mutation_checks))
                self.assertNotIn("new-private-status", json.dumps(runner.source_mutation_checks))

    def test_build_accepts_unchanged_dirty_state_and_rejects_each_new_mutation(self):
        for mutation in (None, "tree", "index", "status"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                runner, root, derived = self.runner(directory, mutation=mutation, dirty=True)
                with patch.object(runner, "validate_package_resolution_context", return_value={}):
                    if mutation:
                        with self.assertRaises(zb.QualificationError) as error:
                            runner.build(root, derived, "final-build", "failed-migration", {"derived": str(derived)})
                        self.assertEqual(error.exception.outcome, "failed-safety")
                    else:
                        self.assertEqual(len(runner.build(root, derived, "final-build", "failed-migration", {"derived": str(derived)})["products"]), 3)
                self.assertEqual(runner.source_mutation_checks["final-build"]["statusChanged"], mutation == "status")

    def test_failed_command_outcome_is_preserved_only_when_source_is_unchanged(self):
        for kind in ("scheme", "settings", "build"):
            for mutation in (None, "tree"):
                with self.subTest(kind=kind, mutation=mutation), tempfile.TemporaryDirectory() as directory:
                    runner, root, derived = self.runner(directory, mutation=mutation, fail=True)
                    with self.assertRaises(zb.QualificationError) as error:
                        if kind == "scheme": runner.discover_scheme(root, "scheme")
                        elif kind == "settings": runner.settings(root, "baseline", {"AFNetworking"})
                        else: runner.build(root, derived, "baseline-build", "inconclusive-baseline")
                    self.assertEqual(error.exception.outcome, "failed-safety" if mutation else "inconclusive-baseline")
                    if not mutation: self.assertEqual(str(error.exception), "probe failed")
                    self.assertTrue(all(e["treeChanged"] == bool(mutation) for e in runner.source_mutation_checks.values()))
                    self.assertTrue(runner.source_mutation_checks)

    def test_failed_settings_persist_individual_and_aggregate_report_without_build(self):
        with tempfile.TemporaryDirectory() as directory, ExitStack() as patches:
            runner, root, _ = self.runner(directory, mutation="tree")
            # Point the controlled probe at the actual baseline source created by run().
            original_execute = runner.execute.side_effect

            def execute(label, command, **kwargs):
                baseline = runner.private / "baseline-source"
                if "-showBuildSettings" in command:
                    (baseline / "unexpected").write_text("private source bytes")
                return original_execute(label, command, **kwargs)

            runner.execute.side_effect = execute
            build = self.prepare_run(runner, patches)
            with self.assertRaises(zb.QualificationError): runner.run({"artifact": {}})
            build.assert_not_called()
            summary = json.loads((runner.report / "summary.json").read_text())
            evidence = summary["sourceMutationChecks"]
            self.assertEqual(set(evidence), {f"baseline-{zb.TARGET}-settings", "baseline-settings-group", "baseline-probes-build"})
            self.assertTrue(all(e["treeChanged"] and e["changes"][0]["path"] == "unexpected" for e in evidence.values()))
            self.assertEqual(summary["status"], "failed-safety")
            self.assertNotIn("baselineBuild", summary)

    def test_dirty_or_changed_baseline_is_rejected_before_settings_and_build(self):
        for mutation in ("dirty", "untracked-directory"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory, ExitStack() as patches:
                runner, _, _ = self.runner(directory, dirty=mutation == "dirty")
                build = self.prepare_run(runner, patches)
                if mutation == "untracked-directory":
                    def clone(path, _label):
                        path.mkdir(); (path / "git-invisible-directory").mkdir(); return {}
                    runner.clone_source.side_effect = clone
                settings = patches.enter_context(patch.object(runner, "settings"))
                with self.assertRaises(zb.QualificationError) as error: runner.run({"artifact": {}})
                self.assertEqual(error.exception.outcome, "failed-safety")
                self.assertIn("before probes", str(error.exception))
                settings.assert_not_called(); build.assert_not_called(); runner.execute.assert_not_called()



class BuildSettingsTests(unittest.TestCase):
    def test_requires_every_expected_target_at_15(self):
        docs = [{"target": name, "buildSettings": {"IPHONEOS_DEPLOYMENT_TARGET": "15.0"}} for name in {zb.TARGET, *zb.SIBLINGS}]
        self.assertEqual(set(zb.validate_effective_settings(docs, {zb.TARGET, *zb.SIBLINGS})), {zb.TARGET, *zb.SIBLINGS})
        docs[0]["buildSettings"]["IPHONEOS_DEPLOYMENT_TARGET"] = "13.0"
        with self.assertRaises(zb.QualificationError): zb.validate_effective_settings(docs, {zb.TARGET, *zb.SIBLINGS})


class FinalDeltaTests(unittest.TestCase):
    def test_allows_dependency_outputs_but_rejects_scheme_or_source_changes(self):
        before = {"Podfile": {"kind": "file", "sha256": "a"},
                  zb.SCHEME_DESTINATION: {"kind": "file", "sha256": zb.SCHEME_SHA256},
                  "ZBNetworking/ZBNetworking.h": {"kind": "file", "sha256": "source"}}
        after = json.loads(json.dumps(before))
        after["Podfile"]["sha256"] = "b"
        after["Pods/Manifest.lock"] = {"kind": "file", "sha256": "lock"}
        zb.validate_final_delta(before, after)
        after[zb.SCHEME_DESTINATION]["sha256"] = "changed"
        with self.assertRaises(zb.QualificationError): zb.validate_final_delta(before, after)


if __name__ == "__main__":
    unittest.main()
