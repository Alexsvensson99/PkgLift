"""Offline negative tests for the partial-migration pilot acceptance guards."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
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
    def test_helper_imports_preserve_a_clean_checkout_without_bytecode_override(self):
        with tempfile.TemporaryDirectory(prefix="pkglift-partial-import-") as directory:
            root = Path(directory)
            scripts = root / "Scripts"
            scripts.mkdir()
            for name in ("run-partial-migration-pilot.py", "run-registry-consumer-pilot.py",
                         "capture-environment.py"):
                shutil.copyfile(ROOT / "Scripts" / name, scripts / name)
            before = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}
            environment = dict(os.environ)
            environment.pop("PYTHONDONTWRITEBYTECODE", None)
            environment.pop("PYTHONPYCACHEPREFIX", None)
            subprocess.run(
                [sys.executable, "-c", """
import importlib.util
from pathlib import Path
import runpy
import sys
root = Path(sys.argv[1])
assert not sys.dont_write_bytecode
runpy.run_path(str(root / 'Scripts/run-partial-migration-pilot.py'))
spec = importlib.util.spec_from_file_location('capture_environment', root / 'Scripts/capture-environment.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
""", str(root)], env=environment, check=True, capture_output=True, text=True,
            )
            after = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}
            self.assertEqual(after, before)
            self.assertFalse(list(root.rglob("__pycache__")))

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
        state = pilot.check_linkage(self.document, self.case)
        self.assertEqual(set(state), {self.case["migrate"], *self.case.get("existing", [])})

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


class CoexistenceGuardsTests(LinkageGuardsTests):
    def setUp(self):
        super().setUp()
        self.case = pilot.CASES["PartialSwiftCoexistence"]
        self.add_package("DeviceKit", "EXISTING")

    def add_package(self, name, prefix):
        objects = self.document["objects"]
        product_id = f"{prefix}_PRODUCT"
        reference_id = f"{prefix}_PACKAGE"
        build_file_id = f"{prefix}_BUILD_FILE"
        objects[product_id] = {
            "isa": "XCSwiftPackageProductDependency",
            "productName": name,
            "package": reference_id,
        }
        objects[reference_id] = {
            "isa": "XCRemoteSwiftPackageReference",
            "repositoryURL": pilot.REPOSITORIES[name],
            "requirement": {
                "kind": "exactVersion",
                "version": pilot.VERSIONS[name],
            },
        }
        objects[build_file_id] = {"isa": "PBXBuildFile", "productRef": product_id}
        objects["PROJECT"]["packageReferences"].append(reference_id)
        objects["TARGET"]["packageProductDependencies"].append(product_id)
        objects["FRAMEWORKS"]["files"].append(build_file_id)
        return product_id, reference_id, build_file_id

    def existing_document(self):
        document = copy.deepcopy(self.document)
        objects = document["objects"]
        for key in ("PRODUCT", "PACKAGE", "PRODUCT_BUILD_FILE"):
            del objects[key]
        objects["PROJECT"]["packageReferences"].remove("PACKAGE")
        objects["TARGET"]["packageProductDependencies"].remove("PRODUCT")
        objects["FRAMEWORKS"]["files"].remove("PRODUCT_BUILD_FILE")
        return document

    def existing_state(self):
        return pilot.check_packages(self.existing_document(), self.case, ["DeviceKit"])

    def test_accepts_reviewed_existing_and_migrated_package_graph(self):
        state = pilot.check_linkage(self.document, self.case)
        self.assertEqual(set(state), {"DeviceKit", "KeychainAccess"})

    def test_rejects_lost_existing_package_product(self):
        del self.document["objects"]["EXISTING_PRODUCT"]
        with self.assertRaisesRegex(RuntimeError, "Duplicate/wrong package product"):
            self.existing_state()

    def test_rejects_duplicate_existing_package_product(self):
        self.document["objects"]["EXISTING_PRODUCT_DUPLICATE"] = copy.deepcopy(
            self.document["objects"]["EXISTING_PRODUCT"]
        )
        with self.assertRaisesRegex(RuntimeError, "Duplicate/wrong package product"):
            self.existing_state()

    def test_rejects_lost_or_duplicate_existing_package_reference(self):
        del self.document["objects"]["EXISTING_PACKAGE"]
        with self.assertRaisesRegex(RuntimeError, "Duplicate/wrong package reference"):
            self.existing_state()

        self.setUp()
        self.document["objects"]["EXISTING_PACKAGE_DUPLICATE"] = copy.deepcopy(
            self.document["objects"]["EXISTING_PACKAGE"]
        )
        with self.assertRaisesRegex(RuntimeError, "Duplicate/wrong package reference"):
            self.existing_state()

    def test_rejects_unowned_existing_package_reference(self):
        self.document["objects"]["PROJECT"]["packageReferences"] = ["PACKAGE"]
        with self.assertRaisesRegex(RuntimeError, "Package not owned by project"):
            self.existing_state()

    def test_rejects_lost_or_duplicate_existing_package_link(self):
        self.document["objects"]["FRAMEWORKS"]["files"].remove("EXISTING_BUILD_FILE")
        with self.assertRaisesRegex(RuntimeError, "SwiftPM product must link exactly once"):
            self.existing_state()

        self.setUp()
        self.document["objects"]["EXISTING_BUILD_FILE_DUPLICATE"] = copy.deepcopy(
            self.document["objects"]["EXISTING_BUILD_FILE"]
        )
        self.document["objects"]["FRAMEWORKS"]["files"].append("EXISTING_BUILD_FILE_DUPLICATE")
        with self.assertRaisesRegex(RuntimeError, "SwiftPM product must link exactly once"):
            self.existing_state()

    def test_rejects_changed_existing_requirement(self):
        self.document["objects"]["EXISTING_PACKAGE"]["requirement"]["version"] = "5.8.1"
        with self.assertRaisesRegex(RuntimeError, "Migration changed the pinned requirement"):
            self.existing_state()

    def test_rejects_changed_existing_project_objects(self):
        baseline = pilot.check_packages(self.existing_document(), self.case, ["DeviceKit"])
        migrated = pilot.check_linkage(self.document, self.case)
        migrated["DeviceKit"]["EXISTING_PRODUCT"]["productName"] = "ChangedDeviceKit"
        with self.assertRaisesRegex(RuntimeError, "Existing SwiftPM project objects changed"):
            pilot.check_existing_packages(baseline, migrated)

    @unittest.skipUnless(sys.platform == "darwin", "plutil fixture parsing requires macOS")
    def test_actual_coexistence_fixture_has_the_reviewed_existing_graph(self):
        project = ROOT / "Fixtures/PartialSwiftCoexistence/SwiftKeychainAccess.xcodeproj/project.pbxproj"
        document = json.loads(subprocess.check_output(
            ["plutil", "-convert", "json", "-o", "-", str(project)], text=True
        ))
        state = pilot.check_packages(document, self.case, ["DeviceKit"])
        self.assertEqual(set(state), {"DeviceKit"})


class ResolvedCoexistenceGuardsTests(unittest.TestCase):
    def write_resolved(self, directory, pins):
        path = Path(directory) / "Package.resolved"
        path.write_text(json.dumps({"pins": pins}))
        return path

    @staticmethod
    def pin(name):
        return {
            "identity": name.lower(),
            "kind": "remoteSourceControl",
            "location": pilot.REPOSITORIES[name],
            "state": {"revision": pilot.REVISIONS[name], "version": pilot.VERSIONS[name]},
        }

    def test_accepts_existing_and_migrated_pins_and_returns_them_by_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_resolved(directory, [self.pin("DeviceKit"), self.pin("KeychainAccess")])
            found, pins = pilot.check_resolved(Path(directory), ["DeviceKit", "KeychainAccess"])
        self.assertEqual(found, path)
        self.assertEqual(set(pins), {"devicekit", "keychainaccess"})

    def test_rejects_missing_extra_or_duplicate_pinned_dependencies(self):
        cases = {
            "missing": [self.pin("DeviceKit")],
            "extra": [self.pin("DeviceKit"), self.pin("KeychainAccess"), self.pin("SDWebImage")],
            "duplicate": [self.pin("DeviceKit"), self.pin("KeychainAccess"), self.pin("DeviceKit")],
        }
        for name, pins in cases.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                self.write_resolved(directory, pins)
                with self.assertRaisesRegex(RuntimeError, "Unexpected resolved SwiftPM dependency set"):
                    pilot.check_resolved(Path(directory), ["DeviceKit", "KeychainAccess"])

    def test_rejects_changed_existing_pin(self):
        with tempfile.TemporaryDirectory() as directory:
            pin = self.pin("DeviceKit")
            pin["state"]["revision"] = "0" * 40
            self.write_resolved(directory, [pin, self.pin("KeychainAccess")])
            with self.assertRaisesRegex(RuntimeError, "Unexpected resolved SwiftPM dependency"):
                pilot.check_resolved(Path(directory), ["DeviceKit", "KeychainAccess"])


if __name__ == "__main__":
    unittest.main()
