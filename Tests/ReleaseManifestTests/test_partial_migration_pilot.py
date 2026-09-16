"""Offline negative tests for the partial-migration pilot acceptance guards."""
import copy
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest import mock
import uuid


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "Scripts/run-partial-migration-pilot.py"
SPEC = importlib.util.spec_from_file_location("run_partial_migration_pilot", MODULE_PATH)
pilot = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(pilot)


class OutputGuardTests(unittest.TestCase):
    def test_rejects_output_inside_checkout_before_creation_or_subprocess(self):
        output = ROOT / f".partial-migration-output-{uuid.uuid4()}"
        self.assertFalse(output.exists())

        with mock.patch.object(
            sys,
            "argv",
            [
                "run-partial-migration-pilot.py",
                "--case", "PartialSwift",
                "--output", str(output),
                "--pkglift", sys.executable,
            ],
        ), mock.patch.object(
            pilot.Path,
            "mkdir",
            side_effect=AssertionError("rejected output must not be created"),
        ) as mkdir, mock.patch.object(
            pilot.subprocess,
            "run",
            side_effect=AssertionError("subprocess must not run before output guard"),
        ) as subprocess_run, mock.patch.object(
            pilot.subprocess,
            "check_output",
            side_effect=AssertionError("subprocess must not run before output guard"),
        ) as subprocess_check_output:
            with self.assertRaisesRegex(RuntimeError, "Output must be outside the source checkout"):
                pilot.main()

        mkdir.assert_not_called()
        subprocess_run.assert_not_called()
        subprocess_check_output.assert_not_called()
        self.assertFalse(output.exists())


class PlanGuardsTests(unittest.TestCase):
    def setUp(self):
        self.case = pilot.CASES["PartialSwift"]
        migrate = self.case["migrate"]
        retain = self.case["retain"]
        self.analysis = {
            "candidates": [
                {"pod": {"name": migrate, "isDirect": True}, "classification": "AUTO"},
                {"pod": {"name": retain, "isDirect": True}, "classification": "BLOCKED"},
            ]
        }
        self.plan = {
            "entries": [
                {
                    "podName": migrate,
                    "classification": "AUTO",
                    "targetName": self.case["target"],
                    "targetSourceProfile": {
                        "completeness": "complete",
                        "languages": self.case["languages"],
                    },
                    "packageCandidate": {"products": [migrate]},
                },
                {
                    "podName": retain,
                    "classification": "BLOCKED",
                    "reasonDetails": [{"code": "configuration_denied"}],
                },
            ]
        }

    def test_accepts_reviewed_partial_plan(self):
        self.assertIsNone(pilot.check_plan(self.analysis, self.plan, self.case))

    def test_rejects_changed_analysis_auto_set(self):
        self.analysis["candidates"][0]["classification"] = "REVIEW"
        with self.assertRaisesRegex(RuntimeError, "Reviewed analysis AUTO set changed"):
            pilot.check_plan(self.analysis, self.plan, self.case)

    def test_rejects_retained_dependency_becoming_auto_in_plan(self):
        self.plan["entries"][1]["classification"] = "AUTO"
        with self.assertRaisesRegex(RuntimeError, "Reviewed plan AUTO set changed"):
            pilot.check_plan(self.analysis, self.plan, self.case)

    def test_rejects_duplicate_plan_entry(self):
        self.plan["entries"].append(copy.deepcopy(self.plan["entries"][1]))
        with self.assertRaisesRegex(RuntimeError, "Duplicate or unexpected plan entry"):
            pilot.check_plan(self.analysis, self.plan, self.case)


class LockGuardsTests(unittest.TestCase):
    @staticmethod
    def lock(*roots):
        pods = "\n".join(f"  - {name} ({version})" for name, version in roots)
        dependencies = "\n".join(f"  - {name} (= {version})" for name, version in roots)
        return f"PODS:\n{pods}\n\nDEPENDENCIES:\n{dependencies}\n\nSPEC REPOS:\n"

    def test_accepts_expected_roots_versions_and_direct_declarations(self):
        lock = self.lock(("KeychainAccess", "4.2.2"), ("SDWebImage", "5.18.1"))
        self.assertIsNone(pilot.check_lock(lock, ["KeychainAccess", "SDWebImage"]))

    def test_rejects_wrong_pinned_version(self):
        lock = self.lock(("KeychainAccess", "4.2.3"), ("SDWebImage", "5.18.1"))
        with self.assertRaisesRegex(RuntimeError, "Pinned dependency version changed"):
            pilot.check_lock(lock, ["KeychainAccess", "SDWebImage"])

    def test_rejects_unexpected_locked_root(self):
        lock = self.lock(
            ("KeychainAccess", "4.2.2"),
            ("SDWebImage", "5.18.1"),
            ("UnexpectedPod", "1.0.0"),
        )
        with self.assertRaisesRegex(RuntimeError, "Unexpected locked dependency roots"):
            pilot.check_lock(lock, ["KeychainAccess", "SDWebImage"])


class LinkageGuardsTests(unittest.TestCase):
    def setUp(self):
        self.case = pilot.CASES["PartialSwift"]
        target = self.case["target"]
        migrated = self.case["migrate"]
        support = f"Target Support Files/Pods-{target}"
        self.document = {
            "rootObject": "PROJECT",
            "objects": {
                "PROJECT": {
                    "isa": "PBXProject",
                    "packageReferences": ["PACKAGE"],
                },
                "TARGET": {
                    "isa": "PBXNativeTarget",
                    "name": target,
                    "productName": target,
                    "productType": "com.apple.product-type.application",
                    "productReference": "APP_PRODUCT",
                    "packageProductDependencies": ["PRODUCT"],
                    "buildPhases": ["SOURCES", "FRAMEWORKS", "RESOURCES", "PODS_CHECK"],
                    "buildConfigurationList": "CONFIG_LIST",
                },
                "APP_PRODUCT": {
                    "isa": "PBXFileReference",
                    "path": f"{target}.app",
                },
                "PRODUCT": {
                    "isa": "XCSwiftPackageProductDependency",
                    "productName": migrated,
                    "package": "PACKAGE",
                },
                "PACKAGE": {
                    "isa": "XCRemoteSwiftPackageReference",
                    "repositoryURL": pilot.REPOSITORIES[migrated],
                    "requirement": {
                        "kind": "exactVersion",
                        "version": pilot.VERSIONS[migrated],
                    },
                },
                "FRAMEWORKS": {
                    "isa": "PBXFrameworksBuildPhase",
                    "files": ["PRODUCT_BUILD_FILE"],
                },
                "PRODUCT_BUILD_FILE": {
                    "isa": "PBXBuildFile",
                    "productRef": "PRODUCT",
                },
                "SOURCES": {
                    "isa": "PBXSourcesBuildPhase",
                    "files": ["SOURCE_BUILD_FILE"],
                },
                "SOURCE_BUILD_FILE": {
                    "isa": "PBXBuildFile",
                    "fileRef": "SOURCE_FILE",
                },
                "SOURCE_FILE": {
                    "isa": "PBXFileReference",
                    "path": "AppDelegate.swift",
                },
                "RESOURCES": {
                    "isa": "PBXResourcesBuildPhase",
                    "files": ["RESOURCE_BUILD_FILE"],
                },
                "RESOURCE_BUILD_FILE": {
                    "isa": "PBXBuildFile",
                    "fileRef": "RESOURCE_FILE",
                },
                "RESOURCE_FILE": {
                    "isa": "PBXFileReference",
                    "path": "Fixture.txt",
                },
                "PODS_CHECK": {
                    "isa": "PBXShellScriptBuildPhase",
                    "name": "[CP] Check Pods Manifest.lock",
                    "shellScript": 'diff "${PODS_PODFILE_DIR_PATH}/Podfile.lock" "${PODS_ROOT}/Manifest.lock"',
                },
                "CONFIG_LIST": {
                    "isa": "XCConfigurationList",
                    "buildConfigurations": ["DEBUG", "RELEASE"],
                },
                "DEBUG": {
                    "isa": "XCBuildConfiguration",
                    "name": "Debug",
                    "baseConfigurationReference": "DEBUG_CONFIG",
                },
                "RELEASE": {
                    "isa": "XCBuildConfiguration",
                    "name": "Release",
                    "baseConfigurationReference": "RELEASE_CONFIG",
                },
                "DEBUG_CONFIG": {
                    "isa": "PBXFileReference",
                    "path": f"{support}/Pods-{target}.debug.xcconfig",
                },
                "RELEASE_CONFIG": {
                    "isa": "PBXFileReference",
                    "path": f"{support}/Pods-{target}.release.xcconfig",
                },
            },
        }

    def test_accepts_reviewed_partial_linkage(self):
        self.assertIsNone(pilot.check_linkage(self.document, self.case))

    def test_protected_project_state_accepts_unchanged_document(self):
        self.assertEqual(
            pilot.protected_project_state(self.document),
            pilot.protected_project_state(copy.deepcopy(self.document)),
        )

    def test_rejects_missing_retained_cocoapods_check_phase(self):
        self.document["objects"]["TARGET"]["buildPhases"].remove("PODS_CHECK")
        with self.assertRaisesRegex(RuntimeError, "CocoaPods check phase lost"):
            pilot.check_linkage(self.document, self.case)

    def test_rejects_lost_retained_cocoapods_base_configuration(self):
        self.document["objects"]["DEBUG_CONFIG"]["path"] = "Configs/App.debug.xcconfig"
        with self.assertRaisesRegex(RuntimeError, "CocoaPods base configuration lost"):
            pilot.check_linkage(self.document, self.case)

    def test_rejects_duplicate_swiftpm_product_objects(self):
        self.document["objects"]["DUPLICATE_PRODUCT"] = copy.deepcopy(
            self.document["objects"]["PRODUCT"]
        )
        with self.assertRaisesRegex(RuntimeError, "Duplicate/wrong package product"):
            pilot.check_linkage(self.document, self.case)

    def test_rejects_swiftpm_product_not_attached_to_consumer_target(self):
        self.document["objects"]["TARGET"]["packageProductDependencies"] = []
        with self.assertRaisesRegex(RuntimeError, "Product attached to wrong target"):
            pilot.check_linkage(self.document, self.case)

    def test_rejects_changed_source_membership(self):
        baseline = pilot.protected_project_state(self.document)
        changed = copy.deepcopy(self.document)
        changed["objects"]["SOURCES"]["files"] = []
        with self.assertRaisesRegex(
            RuntimeError,
            "Consumer source/resource membership or target settings changed",
        ):
            pilot.require(
                pilot.protected_project_state(changed) == baseline,
                "Consumer source/resource membership or target settings changed",
            )


if __name__ == "__main__":
    unittest.main()
