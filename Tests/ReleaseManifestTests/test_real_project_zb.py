import importlib.util
import json
import unittest
from pathlib import Path

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
    plan = {"projectPath": str(root / zb.PROJECT), "entries": [
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


class PlanTests(unittest.TestCase):
    def test_accepts_only_sd_auto_for_objc_app(self):
        analysis, plan = analysis_plan()
        self.assertEqual(zb.validate_analysis_and_plan(analysis, plan, Path("/tmp/source"))["auto"], ["SDWebImage"])

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
