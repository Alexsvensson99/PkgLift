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
                (root / zb.WORKSPACE / "xcshareddata").mkdir(parents=True)
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
                self.assertEqual(list((root / zb.SWIFTPM_SETUP_DIRECTORIES[-1]).iterdir()), [])
                for path in zb.SWIFTPM_SETUP_DIRECTORIES:
                    self.assertEqual(after[path], {"kind": "directory", "mode": 0o777})
                snapshots.append(result)
            self.assertEqual(snapshots[0], snapshots[1])

    def test_rejects_any_existing_setup_path_without_modifying_it(self):
        for kind in ("empty-directory", "nonempty-directory", "file", "symlink"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                parent = root / zb.WORKSPACE / "xcshareddata"; parent.mkdir(parents=True)
                path = root / zb.SWIFTPM_SETUP_DIRECTORIES[0]
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

    def test_rejects_symlinked_parent_without_writing_outside_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"; root.mkdir()
            outside = Path(directory) / "outside"; (outside / "xcshareddata").mkdir(parents=True)
            (root / zb.WORKSPACE).symlink_to(outside, target_is_directory=True)
            before = zb.tree_snapshot(Path(directory))
            with self.assertRaises(zb.QualificationError): self.runner(root).prepare_swiftpm_directories(root)
            self.assertEqual(zb.tree_snapshot(Path(directory)), before)

    def test_rejects_unexpected_extra_file_during_setup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / zb.WORKSPACE / "xcshareddata").mkdir(parents=True)
            original = Path.mkdir

            def mkdir(path, *args, **kwargs):
                original(path, *args, **kwargs)
                if path.name == "configuration": (path / "unexpected").write_text("extra")

            with patch.object(Path, "mkdir", mkdir), self.assertRaises(zb.QualificationError) as error:
                self.runner(root).prepare_swiftpm_directories(root)
            self.assertEqual(error.exception.outcome, "failed-safety")

    def test_discovery_still_rejects_file_created_inside_prepared_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / zb.WORKSPACE / "xcshareddata").mkdir(parents=True)
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
            result = runner.settings(root, "final", {"AFNetworking"})
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
                if mutation:
                    with self.assertRaises(zb.QualificationError) as error:
                        runner.build(root, derived, "final-build", "failed-migration")
                    self.assertEqual(error.exception.outcome, "failed-safety")
                else:
                    self.assertEqual(len(runner.build(root, derived, "final-build", "failed-migration")["products"]), 3)
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
