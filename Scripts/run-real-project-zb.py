#!/usr/bin/env python3
"""Fail-closed G3 runner for Suzhibin/ZBNetworking at one exact commit.

Only ``report/`` is portable. Upstream source, dependencies, command output,
Pods, DerivedData, and the generated Specs cache remain below ``private/``.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Mapping

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
AWS_PATH = ROOT / "Scripts/run-real-project-aws.py"
INTAKE = ROOT / "Documentation/Evidence/MultiTargetQualification-1.0/zb-execution-intake.json"
INTAKE_SHA256 = "1e3813a384755bd5360440a3b85c01523a73af99a273b409bb1698a5cee6abbd"
_SPEC = importlib.util.spec_from_file_location("pkglift_g3_aws_shared", AWS_PATH)
assert _SPEC and _SPEC.loader
shared = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(shared)

QualificationError = shared.QualificationError
require = shared.require
file_sha256 = shared.file_sha256
sha256_bytes = shared.sha256_bytes
tree_snapshot = shared.tree_snapshot
tree_digest = shared.tree_digest
changed_paths = shared.changed_paths
validate_runtime_contract = shared.validate_runtime_contract
exclude_generated_plan = shared.exclude_generated_plan
validate_portable_parity = shared.validate_portable_parity
validate_dry_run = shared.validate_dry_run

REPOSITORY = "https://github.com/Suzhibin/ZBNetworking.git"
SOURCE_COMMIT = "fda54d347a0a8be11cf63e5eea76d0289e3a728d"
SOURCE_TREE = "b8718f5fe44b0b4c153827892eb0606176747267"
SOURCE_LICENSE = "MIT"
PROJECT = "ZBNetworkingDemo.xcodeproj"
WORKSPACE = "ZBNetworkingDemo.xcworkspace"
SWIFTPM_SETUP_DIRECTORIES = (
    f"{PROJECT}/project.xcworkspace/xcshareddata/swiftpm",
    f"{PROJECT}/project.xcworkspace/xcshareddata/swiftpm/configuration",
    f"{WORKSPACE}/xcshareddata/swiftpm",
    f"{WORKSPACE}/xcshareddata/swiftpm/configuration",
)
SWIFTPM_SETUP_MODE = 0o777
TARGET = "ZBNetworkingDemo"
SIBLINGS = ("ZBNetworkingDemoTests", "ZBNetworkingDemoUITests")
POD_VERSIONS = {"AFNetworking": "4.0.1", "SDWebImage": "5.8.4"}
SPECS_COMMIT = "e4af897aa0ddc011a5adc30aa3568aa6ae2ab600"
SPECS_URL = "https://github.com/CocoaPods/Specs.git"
SPECS_METADATA_PATH = "CocoaPods-version.yml"
SPECS_METADATA_URL = f"https://raw.githubusercontent.com/CocoaPods/Specs/{SPECS_COMMIT}/{SPECS_METADATA_PATH}"
SPECS_METADATA_SHA256 = "4d1dc0966425cdd834073ff6852045975d08bf63fd500bfaa0cad2795506c713"
SPECS_METADATA_BYTES = b"---\nmin: 1.0.0\nlast: 1.9.3\nprefix_lengths:\n- 1\n- 1\n- 1\n"
COCOAPODS_VERSION = "1.17.0"
RETAINED_AF_REVIEWED_SOURCE_TREE_SHA256 = "46b246ffa903b939afb8c97185f4475a3740de1ed498706788325f6856788698"
RETAINED_AF_EXPECTED_LOCKED_TREE_SHA256 = "302af4b95d030153d4cbd86ac886b27eb0b3b5384cf440778ee3663cd32e3d35"
RETAINED_AF_FILE_COUNT = 14
RETAINED_AF_REMOVE_MODE_BITS = 0o200
RETAINED_AF_LOCK_MODE_POLICY = {
    "phase": "post-migration-pod-install", "pod": "AFNetworking", "version": "4.0.1",
    "cocoaPods": COCOAPODS_VERSION, "removeModeBits": RETAINED_AF_REMOVE_MODE_BITS,
    "reviewedSourceTreeSHA256": RETAINED_AF_REVIEWED_SOURCE_TREE_SHA256,
    "expectedLockedTreeSHA256": RETAINED_AF_EXPECTED_LOCKED_TREE_SHA256,
    "fileCount": RETAINED_AF_FILE_COUNT,
}
PACKAGE_RESOLVED_PATHS = (
    f"{WORKSPACE}/xcshareddata/swiftpm/Package.resolved",
    f"{PROJECT}/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
)
PACKAGE_URL = "https://github.com/SDWebImage/SDWebImage"
PACKAGE_REVISION = "2f9ef53b99a25bdfba97660c69c42cb54e323b78"
PACKAGE_RESOLVED_DOCUMENT = {"pins": [{"identity": "sdwebimage", "kind": "remoteSourceControl",
    "location": PACKAGE_URL, "state": {"revision": PACKAGE_REVISION, "version": "5.8.4"}}], "version": 2}
PACKAGE_RESOLVED_BYTES = (json.dumps(PACKAGE_RESOLVED_DOCUMENT, indent=2, sort_keys=True) + "\n").encode()
PACKAGE_RESOLVED_SHA256 = "7d81be39079d84cbc2a284c7464b4675b244bf6b125c37a7095088080f502da0"
PACKAGE_MANIFEST_SHA256 = "2e40ec6f0016ac0d08c2d4175d5c4c292bb1c3829589a2a8764d75586084db4a"
AF_REVISION = "ffae2391ab0c29dc88eb0a58d2f5b2c2c27cadbf"
MANIFEST_PHASE_SHA256 = "f27ea9d89e0c46c0d4633696a1334ef50d5a8c9584c538e9eebfb38b0b62e9a7"
SCHEME_SOURCE = f"{PROJECT}/xcuserdata/nquec.xcuserdatad/xcschemes/ZBNetworkingDemo.xcscheme"
SCHEME_DESTINATION = f"{PROJECT}/xcshareddata/xcschemes/ZBNetworkingDemo.xcscheme"
SCHEME_SHA256 = "c379780bc19dca2b862149d7f17cf07117c44f019cd4dff06f8d119227d73032"
TARGET_IDENTITIES = {
    TARGET: {"blueprintID": "7DF8262C1D5815BE000D1109",
             "buildableName": "ZBNetworkingDemo.app",
             "productType": "com.apple.product-type.application"},
    SIBLINGS[0]: {"blueprintID": "7DF826451D5815BE000D1109",
                  "buildableName": "ZBNetworkingDemoTests.xctest",
                  "productType": "com.apple.product-type.bundle.unit-test"},
    SIBLINGS[1]: {"blueprintID": "7DF826501D5815BE000D1109",
                  "buildableName": "ZBNetworkingDemoUITests.xctest",
                  "productType": "com.apple.product-type.bundle.ui-testing"},
}
SCHEME_BUILD_FLAGS = {"buildForTesting": "YES", "buildForRunning": "YES",
                      "buildForProfiling": "YES", "buildForArchiving": "YES",
                      "buildForAnalyzing": "YES"}

PODSPEC_INPUTS = {
    "AFNetworking": {
        "version": "4.0.1", "path": "Specs/a/7/5/AFNetworking/4.0.1/AFNetworking.podspec.json",
        "url": f"https://raw.githubusercontent.com/CocoaPods/Specs/{SPECS_COMMIT}/Specs/a/7/5/AFNetworking/4.0.1/AFNetworking.podspec.json",
        "rawSHA256": "c16319d0d9133f5a7f07444450554d8d97157a2d6b89bf49d731cc5af8247790",
        "rawSHA1": "7864c38297c79aaca1500c33288e429c3451fdce",
        "git": "https://github.com/AFNetworking/AFNetworking.git", "tag": "4.0.1", "revision": AF_REVISION,
    },
    "SDWebImage": {
        "version": "5.8.4", "path": "Specs/1/1/7/SDWebImage/5.8.4/SDWebImage.podspec.json",
        "url": f"https://raw.githubusercontent.com/CocoaPods/Specs/{SPECS_COMMIT}/Specs/1/1/7/SDWebImage/5.8.4/SDWebImage.podspec.json",
        "rawSHA256": "1991b919ea6129e9031d12b691d8134353662141b4a8a0691b9f3a7a0d1c4d34",
        "rawSHA1": "cf6922231e95550934da2ada0f20f2becf2ceba9",
        "git": "https://github.com/SDWebImage/SDWebImage.git", "tag": "5.8.4", "revision": PACKAGE_REVISION,
    },
}

EXPECTED_SOURCE_HASHES = {
    "Podfile": "4e6978b049ad6ca4778fe126ee03695e82f61ad427cab8775986cee29dcd1618",
    "Podfile.lock": "66aa510b37123646b137f5377c4987809d5a33954fcaaf2efe8934e9310b67c3",
    "Pods/Manifest.lock": "66aa510b37123646b137f5377c4987809d5a33954fcaaf2efe8934e9310b67c3",
    f"{PROJECT}/project.pbxproj": "96b0b48d67392ec93d3293dec7dea86ee7a976461753ad21621c6c1e129908c0",
    f"{WORKSPACE}/contents.xcworkspacedata": "6025277185c430e5167f34e206a45a9d4f0b71913edf11a486c88f7ec8b915bc",
}


def validate_execution_intake() -> dict[str, Any]:
    require(INTAKE.is_file() and not INTAKE.is_symlink() and file_sha256(INTAKE) == INTAKE_SHA256,
            "ZB execution intake is missing or changed", "blocked-input")
    try:
        value = json.loads(INTAKE.read_text())
    except ValueError as error:
        raise QualificationError("blocked-input", "ZB execution intake is invalid JSON") from error
    case = value.get("case", {})
    require(value.get("schemaVersion") == 1
            and case == {"id": "zbnetworking-multitarget", "repository": REPOSITORY,
                         "commit": SOURCE_COMMIT, "tree": SOURCE_TREE, "license": SOURCE_LICENSE},
            "execution intake case changed", "blocked-input")
    inventory = value.get("sourceInventory", {})
    require({key: inventory.get(key) for key in ("blobCount", "regularBlobCount", "symlinkBlobCount",
                                                   "executableBlobCount", "submoduleCount")} ==
            {"blobCount": 449, "regularBlobCount": 279, "symlinkBlobCount": 167,
             "executableBlobCount": 3, "submoduleCount": 0}, "execution intake inventory changed", "blocked-input")
    selection = value.get("selection", {})
    require(selection.get("project") == PROJECT and selection.get("workspace") == WORKSPACE
            and selection.get("scheme") == TARGET and selection.get("podsProjectShellPhaseCount") == 0,
            "execution intake selection changed", "blocked-input")
    expected_native_targets = [{"name": name, "blueprintID": identity["blueprintID"],
                                "productType": identity["productType"]}
                               for name, identity in TARGET_IDENTITIES.items()]
    expected_execution_inventory = {
        "applicationProject": {"PBXAggregateTarget": 0, "PBXBuildRule": 0,
                               "PBXLegacyTarget": 0, "PBXNativeTarget": 3,
                               "PBXShellScriptBuildPhase": 1},
        "podsProject": {"PBXAggregateTarget": 0, "PBXBuildRule": 0,
                        "PBXLegacyTarget": 0, "PBXNativeTarget": 3,
                        "PBXShellScriptBuildPhase": 0},
    }
    require(selection.get("nativeTargets") == expected_native_targets
            and selection.get("executionObjectInventory") == expected_execution_inventory,
            "execution intake target/object inventory changed", "blocked-input")
    expected_metadata = {"path": SPECS_METADATA_PATH, "url": SPECS_METADATA_URL,
                         "rawSHA256": SPECS_METADATA_SHA256}
    require(value.get("podfile", {}).get("sha256") == EXPECTED_SOURCE_HASHES["Podfile"]
            and value.get("specs", {}).get("commit") == SPECS_COMMIT
            and value.get("specs", {}).get("metadata") == expected_metadata
            and value.get("swiftPackage", {}).get("revision") == PACKAGE_REVISION
            and value.get("swiftPackage", {}).get("manifestSHA256") == PACKAGE_MANIFEST_SHA256,
            "execution intake dependency closure changed", "blocked-input")
    require(value.get("implementationReview", {}).get("retainedAFLockModePolicy")
            == RETAINED_AF_LOCK_MODE_POLICY,
            "execution intake retained AF lock-mode policy changed", "blocked-input")
    require(value.get("implementationReview", {}).get("packageResolvedInputs") == {
        "paths": list(PACKAGE_RESOLVED_PATHS), "rawSHA256": PACKAGE_RESOLVED_SHA256,
        "schemaVersion": 2, "mode": 0o644},
            "execution intake package resolution inputs changed", "blocked-input")
    require(value.get("implementationReview", {}).get("finalBuildDiagnosticPolicy") == BUILD_DIAGNOSTIC_POLICY,
            "execution intake final-build diagnostic policy changed", "blocked-input")
    swift_package = value.get("swiftPackage", {})
    require(swift_package.get("products") == ["SDWebImage"]
            and {key: swift_package.get(key) for key in ("dependencyCount", "pluginCount", "binaryTargetCount")}
            == {"dependencyCount": 0, "pluginCount": 0, "binaryTargetCount": 0},
            "execution intake SwiftPM closure changed", "blocked-input")
    profile = value.get("buildProfile", {})
    require(profile.get("host") == "macos-15" and profile.get("xcode") == "16.4"
            and profile.get("cocoaPods") == COCOAPODS_VERSION and profile.get("deploymentOverride") == "15.0"
            and profile.get("action") == "build-for-testing" and profile.get("compileOnly") is True,
            "execution intake build profile changed", "blocked-input")
    promotion = value.get("implementationReview", {}).get("schemePromotion", {})
    require(promotion == {"source": SCHEME_SOURCE, "destination": SCHEME_DESTINATION,
                          "sha256": SCHEME_SHA256, "identicalInBothCopies": True,
                          "generatedActions": False}, "execution intake scheme promotion changed", "blocked-input")
    require(value.get("implementationReview", {}).get("swiftPMDirectorySetup") == {
        "paths": list(SWIFTPM_SETUP_DIRECTORIES), "mode": SWIFTPM_SETUP_MODE,
        "evidenceRunIDs": ["35409428336", "35443019152"], "identicalInBothCopies": True,
        "noFilesCreated": True, "rejectExistingPaths": True,
    }, "execution intake SwiftPM directory setup changed", "blocked-input")
    return {"sha256": INTAKE_SHA256, "schemaVersion": 1, "decision": value.get("decision")}


def validate_tag_binding(output: str, tag: str, revision: str) -> None:
    refs = {ref: commit for commit, ref in (line.split("\t", 1) for line in output.splitlines() if "\t" in line)}
    direct = refs.get(f"refs/tags/{tag}")
    peeled = refs.get(f"refs/tags/{tag}^{{}}")
    require((peeled or direct) == revision, f"tag {tag} no longer binds to reviewed commit", "blocked-input")


def parse_lock(text: str) -> dict[str, Any]:
    pods = text.split("PODS:\n", 1)[1].split("\nDEPENDENCIES:", 1)[0] if "PODS:\n" in text else ""
    versions = dict(re.findall(r"^  - ([A-Za-z0-9_+/.-]+) \(([^):]+)", pods, re.MULTILINE))
    deps = text.split("DEPENDENCIES:\n", 1)[1].split("\n\n", 1)[0] if "DEPENDENCIES:\n" in text else ""
    roots = re.findall(r"^  - ([A-Za-z0-9_+.-]+)", deps, re.MULTILINE)
    checksums = text.split("SPEC CHECKSUMS:\n", 1)[1].split("\n\n", 1)[0] if "SPEC CHECKSUMS:\n" in text else ""
    return {"roots": roots, "versions": versions,
            "checksums": dict(re.findall(r"^  ([^:]+): ([0-9a-f]{40})$", checksums, re.MULTILINE))}


def validate_lock(text: str, roots: set[str]) -> dict[str, Any]:
    value = parse_lock(text)
    require(set(value["roots"]) == roots, f"unexpected lock roots: {value['roots']}")
    for name in roots:
        require(value["versions"].get(name) == POD_VERSIONS[name], f"{name} version changed")
        require(value["checksums"].get(name) == PODSPEC_INPUTS[name]["rawSHA1"], f"{name} checksum changed")
    if "SDWebImage" in roots:
        require(value["versions"].get("SDWebImage/Core") == "5.8.4", "SDWebImage/Core changed")
    else:
        require(not any(k.startswith("SDWebImage") for k in value["versions"]), "SDWebImage remains in Pods lock")
    require("EXTERNAL SOURCES:" not in text and "CHECKOUT OPTIONS:" not in text,
            "lock gained an external source")
    return value


def validate_podspec(name: str, raw: bytes) -> dict[str, Any]:
    source = PODSPEC_INPUTS[name]
    require(sha256_bytes(raw) == source["rawSHA256"], f"{name} raw podspec changed", "blocked-input")
    try:
        value = json.loads(raw)
    except ValueError as error:
        raise QualificationError("blocked-input", f"{name} podspec is invalid JSON") from error
    require(value.get("name") == name and str(value.get("version")) == source["version"],
            f"{name} identity changed", "blocked-input")
    spec_source = value.get("source", {})
    require(spec_source.get("git") == source["git"] and str(spec_source.get("tag")) == source["tag"],
            f"{name} source changed", "blocked-input")
    forbidden = {"prepare_command", "script_phase", "script_phases", "vendored_frameworks",
                 "vendored_libraries", "resources", "resource_bundles"}
    require(not (forbidden & set(value)), f"{name} gained executable/binary/resource input", "blocked-input")
    dependencies = value.get("dependencies") or {}
    require(not dependencies, f"{name} gained external pod dependencies", "blocked-input")
    return {"name": name, "version": source["version"], "rawSHA256": source["rawSHA256"],
            "lockChecksum": source["rawSHA1"], "specsCommit": SPECS_COMMIT, "path": source["path"]}


def validate_specs_metadata() -> dict[str, str]:
    require(sha256_bytes(SPECS_METADATA_BYTES) == SPECS_METADATA_SHA256,
            "CocoaPods Specs metadata changed", "blocked-input")
    return {"path": SPECS_METADATA_PATH, "url": SPECS_METADATA_URL,
            "rawSHA256": SPECS_METADATA_SHA256, "specsCommit": SPECS_COMMIT}


def validate_scheme_bytes(raw: bytes) -> dict[str, Any]:
    root = ET.fromstring(raw)
    require(root.tag == "Scheme" and not list(root.iter("ExecutionAction")), "scheme gained execution actions", "blocked-input")
    entries = root.findall("BuildAction/BuildActionEntries/BuildActionEntry")
    require(len(entries) == 1, "scheme BuildAction entry inventory changed", "blocked-input")
    entry = entries[0]
    references = entry.findall("BuildableReference")
    expected_reference = {"BuildableIdentifier": "primary",
                          "BlueprintIdentifier": TARGET_IDENTITIES[TARGET]["blueprintID"],
                          "BuildableName": TARGET_IDENTITIES[TARGET]["buildableName"],
                          "BlueprintName": TARGET,
                          "ReferencedContainer": f"container:{PROJECT}"}
    require(entry.attrib == SCHEME_BUILD_FLAGS and len(references) == 1
            and references[0].attrib == expected_reference,
            "scheme app BuildAction identity/container/flags changed", "blocked-input")
    tests = [node.get("BlueprintName") for node in root.findall("TestAction/Testables/TestableReference/BuildableReference")]
    require(tests == list(SIBLINGS), "scheme test target set changed", "blocked-input")
    return {"app": TARGET, "tests": tests}


def validate_source_intake(root: Path) -> dict[str, Any]:
    for relative, digest in EXPECTED_SOURCE_HASHES.items():
        path = root / relative
        require(path.is_file() and not path.is_symlink() and file_sha256(path) == digest,
                f"reviewed source changed: {relative}", "blocked-input")
    require((root / "LICENSE").is_file() and "MIT License" in (root / "LICENSE").read_text(),
            "MIT license missing", "blocked-input")
    validate_lock((root / "Podfile.lock").read_text(), set(POD_VERSIONS))
    require((root / "Podfile.lock").read_bytes() == (root / "Pods/Manifest.lock").read_bytes(),
            "committed lock and manifest differ", "blocked-input")
    schemes = sorted((root / PROJECT / "xcuserdata").glob("*/xcschemes/ZBNetworkingDemo.xcscheme"))
    require(len(schemes) == 2, "reviewed user-scheme inventory changed", "blocked-input")
    scheme_evidence = [validate_scheme_bytes(path.read_bytes()) | {"sha256": file_sha256(path)} for path in schemes]
    snapshot = tree_snapshot(root)
    symlinks = {path: item for path, item in snapshot.items() if item["kind"] == "symlink"}
    regulars = [item for item in snapshot.values() if item["kind"] == "file"]
    require(len(regulars) == 282 and sum(1 for item in regulars if item["mode"] & 0o111) == 3
            and len(symlinks) == 167, "tracked payload inventory changed", "blocked-input")
    for relative, item in symlinks.items():
        target = item["target"]
        require(not os.path.isabs(target), f"absolute symlink: {relative}", "blocked-input")
        resolved = (root / relative).parent.joinpath(target).resolve(strict=True)
        require(resolved.is_relative_to(root.resolve()), f"escaping symlink: {relative}", "blocked-input")
    return {"commit": SOURCE_COMMIT, "tree": SOURCE_TREE, "license": SOURCE_LICENSE,
            "blobCount": 449, "symlinkCount": 167, "schemes": scheme_evidence,
            "treeSHA256": tree_digest(snapshot)}


def _exact_requirement(value: Any) -> bool:
    return value == {"exact": {"_0": "5.8.4"}}


def validate_analysis_and_plan(analysis: Mapping[str, Any], plan: Mapping[str, Any], root: Path) -> dict[str, Any]:
    root = root.resolve(strict=False)
    project = analysis.get("project", {})
    require(Path(project.get("projectPath", "")).resolve(strict=False) == root / PROJECT
            and Path(project.get("workspacePath", "")).resolve(strict=False) == root / WORKSPACE,
            "analysis selection changed")
    candidates = [x for x in analysis.get("candidates", []) if x.get("pod", {}).get("isDirect")]
    entries = plan.get("entries", [])
    require(plan.get("schemaVersion") == 2, "registry-source plan must use schema 2")
    require({x.get("pod", {}).get("name") for x in candidates} == set(POD_VERSIONS)
            and {x.get("podName") for x in entries} == set(POD_VERSIONS), "direct identity set changed")
    auto_c = [x for x in candidates if str(x.get("classification", "")).upper() == "AUTO"]
    auto_e = [x for x in entries if str(x.get("classification", "")).upper() == "AUTO"]
    require([x["pod"]["name"] for x in auto_c] == ["SDWebImage"]
            and [x["podName"] for x in auto_e] == ["SDWebImage"], "AUTO set is not exactly SDWebImage")
    retained = next(x for x in entries if x["podName"] == "AFNetworking")
    require(str(retained.get("classification", "")).upper() != "AUTO"
            and all(set(action) == {"manual"} for action in retained.get("actions", [])),
            "AFNetworking must remain manual")
    entry = auto_e[0]
    package = entry.get("packageCandidate", {})
    require(entry.get("currentVersion") == "5.8.4" and entry.get("targetName") == TARGET,
            "SDWebImage version/target changed")
    require(package.get("repositoryURL") == PACKAGE_URL and package.get("products") == ["SDWebImage"]
            and _exact_requirement(package.get("versionRequirement")), "package mapping changed")
    languages = {str(v).lower() for v in package.get("supportedConsumerLanguages", [])}
    require("objectivec" in languages, "Objective-C mapping support missing")
    by_name = {next(iter(action)): next(iter(action.values())) for action in entry.get("actions", [])}
    require(set(by_name) == {"removePod", "addSwiftPackage", "linkProduct"}, "action set changed")
    require(by_name["removePod"] == {"name": "SDWebImage"}
            and by_name["addSwiftPackage"].get("repositoryURL") == PACKAGE_URL
            and _exact_requirement(by_name["addSwiftPackage"].get("requirement"))
            and by_name["linkProduct"] == {"repositoryURL": PACKAGE_URL, "productName": "SDWebImage", "targetName": TARGET},
            "SDWebImage actions changed")
    return {"auto": ["SDWebImage"], "retained": ["AFNetworking"], "target": TARGET, "version": "5.8.4"}


def validate_dry_run_output(text: str) -> None:
    require(text.strip().splitlines() == [
        "Dry run mode. Add --apply to execute the migration plan.",
        "1 AUTO migration(s):",
        f"- SDWebImage -> {PACKAGE_URL}",
    ], "dry-run actions changed")


def _objects(project: Mapping[str, Any], isa: str) -> dict[str, Mapping[str, Any]]:
    return {key: value for key, value in project.get("objects", {}).items() if value.get("isa") == isa}


def _validate_native_target_inventory(project: Mapping[str, Any], expected_names: set[str], label: str) -> dict[str, Mapping[str, Any]]:
    objects = project.get("objects", {})
    forbidden_isas = {"PBXBuildRule", "PBXLegacyTarget", "PBXAggregateTarget"}
    require(not any(value.get("isa") in forbidden_isas for value in objects.values()),
            f"{label} gained a build rule or non-native execution target", "blocked-input")
    target_like = {key: value for key, value in objects.items()
                   if isinstance(value.get("isa"), str)
                   and value["isa"].startswith("PBX") and value["isa"].endswith("Target")}
    require(all(value.get("isa") == "PBXNativeTarget" for value in target_like.values()),
            f"{label} gained an unknown target execution class", "blocked-input")
    native_by_id = _objects(project, "PBXNativeTarget")
    require(set(target_like) == set(native_by_id)
            and all(value.get("buildRules") == [] for value in native_by_id.values()),
            f"{label} native target build-rule inventory changed", "blocked-input")
    projects = _objects(project, "PBXProject")
    require(len(projects) == 1 and project.get("rootObject") in projects,
            f"{label} project root inventory changed", "blocked-input")
    root = projects[project["rootObject"]]
    require(root.get("targets") == list(root.get("targets", []))
            and set(root.get("targets", [])) == set(native_by_id),
            f"{label} executable target ownership changed", "blocked-input")
    targets = {value.get("name"): value for value in native_by_id.values()}
    require(len(targets) == len(native_by_id) and set(targets) == expected_names,
            f"{label} native target inventory changed", "blocked-input")
    return targets


def validate_build_execution_inputs(project: Mapping[str, Any], pods_project: Mapping[str, Any],
                                    expected_pod_targets: set[str]) -> dict[str, Any]:
    targets = _validate_native_target_inventory(project, {TARGET, *SIBLINGS}, "application project")
    pod_targets = _validate_native_target_inventory(pods_project, expected_pod_targets, "Pods project")
    phases = _objects(project, "PBXShellScriptBuildPhase")
    require(len(phases) == 1, "app project shell-phase inventory changed", "blocked-input")
    phase_id, phase = next(iter(phases.items()))
    require(phase.get("name") == "[CP] Check Pods Manifest.lock"
            and phase.get("shellPath") == "/bin/sh"
            and sha256_bytes(str(phase.get("shellScript", "")).encode()) == MANIFEST_PHASE_SHA256
            and phase.get("inputPaths") == ["${PODS_PODFILE_DIR_PATH}/Podfile.lock", "${PODS_ROOT}/Manifest.lock"]
            and phase.get("outputPaths") == ["$(DERIVED_FILE_DIR)/Pods-ZBNetworkingDemo-checkManifestLockResult.txt"],
            "manifest-lock phase changed", "blocked-input")
    require(phase_id in targets[TARGET].get("buildPhases", [])
            and all(phase_id not in targets[name].get("buildPhases", []) for name in SIBLINGS),
            "manifest-lock phase ownership changed", "blocked-input")
    require(not _objects(pods_project, "PBXShellScriptBuildPhase"),
            "Pods project gained a shell phase", "blocked-input")
    return {"nativeTargets": sorted(targets), "appShellPhases": [phase["name"]],
            "manifestPhaseSHA256": MANIFEST_PHASE_SHA256,
            "podNativeTargets": sorted(pod_targets), "podsShellPhaseCount": 0}


def _reviewed_package_object_ids(project: Mapping[str, Any]) -> tuple[str | None, str | None, str | None]:
    objects = project.get("objects", {})
    refs = [(key, value) for key, value in _objects(project, "XCRemoteSwiftPackageReference").items()
            if str(value.get("repositoryURL", "")).rstrip("/").removesuffix(".git").lower()
            == PACKAGE_URL.lower()]
    products = [(key, value) for key, value in _objects(project, "XCSwiftPackageProductDependency").items()
                if value.get("productName") == "SDWebImage"]
    if not refs and not products:
        return None, None, None
    require(len(refs) == len(products) == 1,
            "reviewed package object inventory changed", "failed-safety")
    ref_id, ref = refs[0]
    product_id, product = products[0]
    require(ref.get("requirement") == {"kind": "exactVersion", "version": "5.8.4"}
            and product.get("package") == ref_id,
            "reviewed package object identity changed", "failed-safety")
    build_ids = [key for key, value in _objects(project, "PBXBuildFile").items()
                 if value.get("productRef") == product_id]
    require(len(build_ids) == 1, "reviewed package build-file inventory changed", "failed-safety")
    return ref_id, product_id, build_ids[0]


def zb_protected_project_state(project: Mapping[str, Any]) -> dict[str, Any]:
    """Protect ZB execution graph fields omitted by the generic G3 snapshot."""
    objects = project.get("objects", {})
    ref_id, _product_id, package_build_id = _reviewed_package_object_ids(project)
    root_id = project.get("rootObject")
    require(isinstance(root_id, str) and objects.get(root_id, {}).get("isa") == "PBXProject",
            "application project root changed", "failed-safety")
    root = copy.deepcopy(objects[root_id])
    package_refs = root.get("packageReferences", [])
    require(isinstance(package_refs, list), "project packageReferences changed type", "failed-safety")
    if ref_id is not None:
        require(package_refs.count(ref_id) == 1,
                "reviewed package reference is not owned by project root", "failed-safety")
        package_refs = [value for value in package_refs if value != ref_id]
    if package_refs:
        root["packageReferences"] = package_refs
    else:
        root.pop("packageReferences", None)

    native_targets = _objects(project, "PBXNativeTarget")
    frameworks: dict[str, Any] = {}
    framework_build_files: dict[str, Any] = {}
    framework_file_refs: dict[str, Any] = {}
    package_owners: list[tuple[str, str]] = []
    dependencies: dict[str, list[str]] = {}
    target_build_phases: dict[str, list[str]] = {}
    dependency_objects: dict[str, Any] = {}
    proxy_objects: dict[str, Any] = {}
    shell_phases: dict[str, Any] = {}
    for target_id, target in native_targets.items():
        dependencies[target_id] = copy.deepcopy(target.get("dependencies", []))
        target_build_phases[target_id] = copy.deepcopy(target.get("buildPhases", []))
        for dependency_id in dependencies[target_id]:
            dependency = objects.get(dependency_id)
            require(isinstance(dependency, dict) and dependency.get("isa") == "PBXTargetDependency",
                    "target dependency object changed", "failed-safety")
            dependency_objects[dependency_id] = copy.deepcopy(dependency)
            proxy_id = dependency.get("targetProxy")
            require(isinstance(proxy_id, str)
                    and objects.get(proxy_id, {}).get("isa") == "PBXContainerItemProxy",
                    "target dependency proxy changed", "failed-safety")
            proxy_objects[proxy_id] = copy.deepcopy(objects[proxy_id])
        for phase_id in target.get("buildPhases", []):
            phase = objects.get(phase_id, {})
            if phase.get("isa") == "PBXShellScriptBuildPhase":
                shell_phases[phase_id] = copy.deepcopy(phase)
            if phase.get("isa") != "PBXFrameworksBuildPhase":
                continue
            protected_phase = copy.deepcopy(phase)
            protected_files = []
            for build_id in phase.get("files", []):
                if build_id == package_build_id:
                    package_owners.append((target.get("name"), phase_id))
                    continue
                build_file = objects.get(build_id)
                require(isinstance(build_file, dict) and build_file.get("isa") == "PBXBuildFile",
                        "framework build-file object changed", "failed-safety")
                protected_files.append(build_id)
                framework_build_files[build_id] = copy.deepcopy(build_file)
                file_ref = build_file.get("fileRef")
                if isinstance(file_ref, str):
                    require(file_ref in objects, "framework file reference missing", "failed-safety")
                    framework_file_refs[file_ref] = copy.deepcopy(objects[file_ref])
            protected_phase["files"] = protected_files
            frameworks[phase_id] = protected_phase
    if package_build_id is not None:
        require(len(package_owners) == 1 and package_owners[0][0] == TARGET,
                "reviewed package build file is linked outside the app framework phase", "failed-safety")

    metadata = {key: copy.deepcopy(value) for key, value in project.items() if key != "objects"}
    return {"metadata": metadata, "projectRoot": root, "frameworkPhases": frameworks,
            "frameworkBuildFiles": framework_build_files, "frameworkFileReferences": framework_file_refs,
            "targetBuildPhases": target_build_phases, "shellScriptPhases": shell_phases,
            "targetDependencies": dependencies, "dependencyObjects": dependency_objects,
            "containerItemProxies": proxy_objects}


def validate_header_links(root: Path, allowed_pods: set[str]) -> dict[str, Any]:
    headers = root / "Pods/Headers"
    require(headers.is_dir(), "Pods header directory missing", "blocked-input")
    links = [path for path in headers.rglob("*") if path.is_symlink()]
    require(links, "Pods header symlink inventory is empty", "blocked-input")
    pod_roots = {(root / "Pods" / name).resolve(strict=True) for name in allowed_pods}
    for link in links:
        target = os.readlink(link)
        require(not os.path.isabs(target), f"absolute Pods header link: {link.name}", "blocked-input")
        resolved = link.resolve(strict=True)
        require(any(resolved.is_relative_to(pod_root) for pod_root in pod_roots),
                f"foreign/escaping Pods header link: {link.name}", "blocked-input")
    return {"count": len(links), "allowedPods": sorted(allowed_pods)}


def validate_final_delta(before: Mapping[str, Any], after: Mapping[str, Any]) -> list[str]:
    allowed_exact = {"Podfile", "Podfile.lock", f"{PROJECT}/project.pbxproj",
                     f"{WORKSPACE}/contents.xcworkspacedata", "Pods", ".pkglift",
                     f"{PROJECT}/project.xcworkspace", f"{PROJECT}/project.xcworkspace/xcshareddata",
                     f"{PROJECT}/project.xcworkspace/xcshareddata/swiftpm",
                     f"{WORKSPACE}/xcshareddata", f"{WORKSPACE}/xcshareddata/swiftpm"}
    allowed_prefixes = ("Pods/", ".pkglift/", f"{PROJECT}/project.xcworkspace/xcshareddata/swiftpm/",
                        f"{WORKSPACE}/xcshareddata/swiftpm/")
    changes = changed_paths(before, after)
    bad = [path for path in changes if path not in allowed_exact and not path.startswith(allowed_prefixes)]
    require(not bad, "final dependency tooling changed protected paths: " + ", ".join(bad[:10]))
    return changes


def sibling_closure(project: Mapping[str, Any]) -> dict[str, Any]:
    objects = project.get("objects", {})
    targets = {key: value for key, value in _objects(project, "PBXNativeTarget").items()
               if value.get("name") in SIBLINGS}
    require({value.get("name") for value in targets.values()} == set(SIBLINGS), "sibling target set changed")
    selected: dict[str, Any] = {}
    queue = list(targets)
    follow = {"buildConfigurationList", "buildConfigurations", "buildPhases", "files", "fileRef",
              "dependencies", "targetProxy", "productReference"}
    while queue:
        key = queue.pop()
        if key in selected or key not in objects:
            continue
        value = copy.deepcopy(objects[key])
        selected[key] = value
        for field in follow:
            child = value.get(field)
            if isinstance(child, str):
                queue.append(child)
            elif isinstance(child, list):
                queue.extend(x for x in child if isinstance(x, str))
    return selected


def validate_linkage(project: Mapping[str, Any]) -> dict[str, Any]:
    objects = project.get("objects", {})
    targets = _objects(project, "PBXNativeTarget")
    named = {value.get("name"): (key, value) for key, value in targets.items()}
    require(set(named) == {TARGET, *SIBLINGS}, "native target inventory changed")
    refs = _objects(project, "XCRemoteSwiftPackageReference")
    products = _objects(project, "XCSwiftPackageProductDependency")
    matching_refs = [(k, v) for k, v in refs.items()
                     if str(v.get("repositoryURL", "")).rstrip("/").removesuffix(".git").lower()
                     == PACKAGE_URL.lower()]
    matching_products = [(k, v) for k, v in products.items() if v.get("productName") == "SDWebImage"]
    require(len(refs) == len(matching_refs) == 1 and len(products) == len(matching_products) == 1,
            "package reference/product inventory changed")
    requirement = matching_refs[0][1].get("requirement", {})
    require(requirement.get("kind") == "exactVersion" and requirement.get("version") == "5.8.4",
            "Xcode package requirement changed")
    product_id = matching_products[0][0]
    ownership = {}
    for name, (_key, target) in named.items():
        phase_ids = target.get("buildPhases", [])
        files = []
        for phase_id in phase_ids:
            phase = objects.get(phase_id, {})
            if phase.get("isa") == "PBXFrameworksBuildPhase":
                files.extend(objects.get(build_id, {}).get("productRef") for build_id in phase.get("files", []))
        ownership[name] = sum(1 for value in files if value == product_id)
    require(ownership == {TARGET: 1, SIBLINGS[0]: 0, SIBLINGS[1]: 0}, "package product ownership changed")
    return ownership


def validate_effective_settings(documents: Any, expected: set[str]) -> dict[str, str]:
    require(isinstance(documents, list), "build settings output is not a list")
    result = {}
    for item in documents:
        name = item.get("target")
        if name in expected:
            result[name] = str(item.get("buildSettings", {}).get("IPHONEOS_DEPLOYMENT_TARGET"))
    require(set(result) == expected and set(result.values()) == {"15.0"}, "effective deployment target is not 15.0")
    return result


# Only fixed categories and hashes cross the private-log boundary. Unknown
# diagnostics remain useful through their source position and message digest.
BUILD_DIAGNOSTIC_POLICY = {"version": 1, "phase": "failed-final-build", "maxRows": 20, "maxRowsPerStream": 10,
                           "maxScanBytesPerStream": 8 * 1024 * 1024, "maxLineBytes": 8192,
                           "rawMessages": False, "rawPaths": False, "sourceExcerpts": False}
_REVIEWED_DIAGNOSTIC_SUBJECTS = frozenset({"SDWebImage", "AFNetworking", "UIImageView+WebCache.h",
                                        "SDImageCache.h", "SDWebImageManager.h"})


def build_diagnostic_category(message: str) -> str:
    if re.fullmatch(r"['<].+['>] file not found", message): return "header-not-found"
    if re.fullmatch(r"(?:no such module ['\"].+['\"]|module ['\"].+['\"] not found)", message): return "module-not-found"
    if message.startswith("could not build module "): return "module-build-failed"
    if message.startswith("use of undeclared identifier "): return "undeclared-identifier"
    if message.startswith("no member named "): return "missing-member"
    if message.startswith("property ") and " not found " in message: return "missing-property"
    if "incompatible" in message: return "incompatible-types"
    if " is unavailable" in message: return "unavailable-api"
    if message.startswith("Undefined symbols for architecture "): return "undefined-symbols"
    if message.startswith("duplicate symbol"): return "duplicate-symbols"
    if message.startswith("library ") and message.endswith(" not found"): return "library-not-found"
    if message.startswith("framework ") and message.endswith(" not found"): return "framework-not-found"
    if message.startswith("linker command failed"): return "linker-failed"
    return "unclassified-error"


def collect_build_diagnostics(log_paths: Mapping[str, Path], command: Mapping[str, Any],
                              source_root: Path, package_root: Path) -> dict[str, Any]:
    """Read bounded private output without ever returning log text or paths."""
    result: dict[str, Any] = {"policy": BUILD_DIAGNOSTIC_POLICY, "rows": [], "streams": {},
                              "matchedCount": 0, "rowsTruncated": False, "unknownDiagnosticCount": 0}
    unknown_digest = hashlib.sha256()
    seen: dict[tuple[str, str], dict[str, Any]] = {}
    for stream in ("stdout", "stderr"):
        metadata: dict[str, Any] = {"bytes": command[stream + "Bytes"], "sha256": command[stream + "SHA256"]}
        result["streams"][stream] = metadata
        path = log_paths[stream]
        try:
            if path.is_symlink() or not path.is_file():
                metadata["captureStatus"] = "unavailable"
                continue
            if path.stat().st_size != metadata["bytes"] or file_sha256(path) != metadata["sha256"]:
                metadata["captureStatus"] = "log-mismatch"
                continue
            with path.open("rb") as handle:
                data = handle.read(BUILD_DIAGNOSTIC_POLICY["maxScanBytesPerStream"] + 1)
        except OSError:
            metadata["captureStatus"] = "unavailable"
            continue
        limited = len(data) > BUILD_DIAGNOSTIC_POLICY["maxScanBytesPerStream"]
        metadata.update(captureStatus="bounded-prefix" if limited else "complete", scanLimited=limited)
        if not limited and (len(data) != metadata["bytes"] or sha256_bytes(data) != metadata["sha256"]):
            metadata["captureStatus"] = "log-mismatch"
            continue
        if limited:
            data = data[:BUILD_DIAGNOSTIC_POLICY["maxScanBytesPerStream"]]
            data = data[:data.rfind(b"\n") + 1]  # Never parse a truncated record.
        metadata.update(scannedBytes=len(data), oversizedLines=0)
        stream_rows = 0
        for raw in data.splitlines():
            if len(raw) > BUILD_DIAGNOSTIC_POLICY["maxLineBytes"]:
                metadata["oversizedLines"] += 1
                continue
            line = raw.decode("utf-8", errors="replace")
            # Anchoring rejects source excerpts, shell commands and caret rows.
            match = re.fullmatch(r"(.+?):([0-9]{1,8})(?::([0-9]{1,8}))?: (?:fatal error|error): (.+)", line)
            location = None
            if match:
                location, line_number, column, message = match.groups()
                if location != location.strip() or any(ord(c) < 32 for c in location): continue
            else:
                tool = re.fullmatch(r"(?:(?:clang(?:\+\+)?|swiftc|xcodebuild|ld): )?(?:fatal )?error: (.+)", line)
                linker = re.fullmatch(r"(?:ld: )?((?:Undefined symbols for architecture .+:|duplicate symbols?.*|(?:library|framework) .+ not found))", line)
                if not tool and not linker:
                    if re.fullmatch(r"(?:Command .+ failed with a nonzero exit code|\*\* (?:BUILD|TEST BUILD) FAILED \*\*)", line):
                        result["unknownDiagnosticCount"] += 1
                        unknown_digest.update(stream.encode() + b":" + hashlib.sha256(raw).digest())
                    continue
                message = (tool or linker).group(1)
            category = build_diagnostic_category(message)
            if category == "unclassified-error":
                result["unknownDiagnosticCount"] += 1
                unknown_digest.update(stream.encode() + b":" + hashlib.sha256(raw).digest())
            result["matchedCount"] += 1
            key = (stream, sha256_bytes(raw))
            if key in seen:
                seen[key]["occurrences"] += 1
                continue
            if (len(result["rows"]) >= BUILD_DIAGNOSTIC_POLICY["maxRows"]
                    or stream_rows >= BUILD_DIAGNOSTIC_POLICY["maxRowsPerStream"]):
                result["rowsTruncated"] = True
                continue
            row: dict[str, Any] = {"stream": stream, "category": category,
                                   "messageSHA256": sha256_bytes(message.encode()), "lineSHA256": key[1], "occurrences": 1}
            if location:
                row.update(line=int(line_number), column=int(column) if column else None, pathScope="external")
                for scope, root in (("project", source_root), ("package", package_root)):
                    prefix = str(root) + "/"
                    if location.startswith(prefix) and ".." not in Path(location[len(prefix):]).parts:
                        location = location[len(prefix):]
                        row["pathScope"] = scope
                        break
                row["pathSHA256"] = sha256_bytes(location.encode())
            subjects = re.findall(r"['\"]([^'\"]+)['\"]", message)
            if subjects:
                row["subjectSHA256"] = sha256_bytes(subjects[0].encode())
                if subjects[0] in _REVIEWED_DIAGNOSTIC_SUBJECTS:
                    row["reviewedSubject"] = subjects[0]
            result["rows"].append(row)
            seen[key] = row
            stream_rows += 1
    result["unknownAggregateSHA256"] = unknown_digest.hexdigest()
    return result


def source_mutation_evidence(before: Mapping[str, Any], after: Mapping[str, Any],
                             index_before: str, index_after: str, status: str,
                             status_before: str = "") -> dict[str, Any]:
    """Bounded metadata only; never publish file bytes, link targets or Git output."""
    def descriptor(value: Mapping[str, Any] | None) -> dict[str, Any] | None:
        if value is None:
            return None
        result = {key: value[key] for key in ("kind", "mode", "size", "sha256") if key in value}
        if value.get("kind") == "symlink":
            result["targetSHA256"] = sha256_bytes(os.fsencode(value["target"]))
        return result

    changes = changed_paths(before, after)
    rows = []
    for path in changes[:64]:
        # Preserve useful relative structure without publishing an Xcode username.
        portable_path = re.sub(r"(?<=xcuserdata/)[^/]+(?=\.xcuserdatad(?:/|$))", "<user>", path)
        rows.append({"path": portable_path[:1024], "pathTruncated": len(portable_path) > 1024,
                     "pathSHA256": sha256_bytes(os.fsencode(path)),
                     "change": "added" if path not in before else "removed" if path not in after else "modified",
                     "before": descriptor(before.get(path)), "after": descriptor(after.get(path))})
    return {"schemaVersion": 1, "treeChanged": bool(changes),
            "beforeTreeSHA256": tree_digest(before), "afterTreeSHA256": tree_digest(after),
            "changedPathCount": len(changes), "changesTruncated": len(changes) > len(rows), "changes": rows,
            "indexChanged": index_before != index_after,
            "beforeIndexTextSHA256": sha256_bytes(index_before.encode()),
            "afterIndexTextSHA256": sha256_bytes(index_after.encode()),
            "gitStatusDirty": bool(status), "gitStatusTextSHA256": sha256_bytes(status.encode()),
            "beforeStatusTextSHA256": sha256_bytes(status_before.encode()),
            "statusChanged": status_before != status}


class Runner(shared.Runner):
    def __init__(self, contract: Mapping[str, Any], jobs: int):
        super().__init__(contract, jobs)
        self.cp_home = self.private / "cocoapods-home"
        self.spec_bytes: dict[str, bytes] = {}
        self.reference_payloads: dict[str, dict[str, Any]] = {}
        self.scheme_discovery: dict[str, Any] = {}
        self.source_mutation_checks: dict[str, Any] = {}
        self.final_build_diagnostic: dict[str, Any] | None = None

    def execute(self, label: str, command: list[Any], **kwargs) -> Any:
        command_index = len(self.commands)
        if label == "final-build": self.final_build_diagnostic = None
        try:
            return super().execute(label, command, **kwargs)
        finally:
            if label == "final-build" and len(self.commands) == command_index + 1:
                record = self.commands[command_index]
                if record.get("label") == label and record.get("exitCode"):
                    try:
                        logs = {stream: self.private / "logs" / f"{command_index + 1:02d}-{label}.{suffix}"
                                for stream, suffix in (("stdout", "out"), ("stderr", "err"))}
                        self.final_build_diagnostic = collect_build_diagnostics(logs, record,
                            self.private / "migration-source",
                            self.private / "final-derived/SourcePackages/checkouts/SDWebImage")
                    except Exception:
                        # Reporting must not replace the command error or skip
                        # the build's finally safety checks. Never expose error text.
                        self.final_build_diagnostic = {"policy": BUILD_DIAGNOSTIC_POLICY,
                                                       "captureStatus": "unavailable"}

    def clone_exact(self, repository: str, commit: str, destination: Path, label: str) -> None:
        destination.mkdir(parents=True)
        self.execute(label + "-init", ["git", "-c", "init.templateDir=", "init", "--quiet", destination])
        self.execute(label + "-hooks", ["git", "-C", destination, "config", "core.hooksPath", "/dev/null"])
        self.execute(label + "-remote", ["git", "-C", destination, "remote", "add", "origin", repository])
        self.execute(label + "-fetch", ["git", "-C", destination, "-c", "credential.helper=", "fetch", "--quiet",
                                               "--depth", "1", "--no-tags", "origin", commit], timeout=300, outcome="blocked-input")
        self.execute(label + "-checkout", ["git", "-C", destination, "checkout", "--quiet", "--detach", "FETCH_HEAD"])
        self.execute(label + "-remove-remote", ["git", "-C", destination, "remote", "remove", "origin"])
        require(self.git(destination, ["rev-parse", "HEAD"]).strip() == commit
                and not self.git(destination, ["status", "--porcelain", "--untracked-files=all"])
                and not self.git(destination, ["remote"]), f"{label} clone provenance changed", "blocked-input")
        modes = self.git(destination, ["ls-files", "--stage"])
        require(not any(line.startswith("160000 ") for line in modes.splitlines()),
                f"{label} contains an unreviewed submodule", "blocked-input")
        clone_root = destination.resolve(strict=True)
        for current, directories, files in os.walk(destination, followlinks=False):
            if Path(current) == destination:
                directories[:] = [name for name in directories if name != ".git"]
            for name in [*directories, *files]:
                path = Path(current) / name
                if path.is_symlink():
                    require(not os.path.isabs(os.readlink(path))
                            and path.resolve(strict=True).is_relative_to(clone_root),
                            f"{label} contains a foreign/escaping symlink", "blocked-input")

    def clone_source(self, destination: Path, label: str) -> dict[str, Any]:
        self.clone_exact(REPOSITORY, SOURCE_COMMIT, destination, label)
        require(self.git(destination, ["rev-parse", "HEAD^{tree}"]).strip() == SOURCE_TREE,
                "upstream tree changed", "blocked-input")
        return validate_source_intake(destination)

    def fetch_inputs(self) -> dict[str, Any]:
        evidence = []
        for name, source in PODSPEC_INPUTS.items():
            try:
                with urllib.request.urlopen(urllib.request.Request(source["url"], headers={"User-Agent": "PkgLift-G3/1"}), timeout=30) as response:
                    raw = response.read(2 * 1024 * 1024)
                    require(not response.read(1), f"{name} podspec too large", "blocked-input")
            except OSError as error:
                raise QualificationError("blocked-input", f"unable to fetch {name} podspec") from error
            self.spec_bytes[name] = raw
            evidence.append(validate_podspec(name, raw))
            tag = self.execute(name.lower() + "-tag-binding",
                ["git", "-c", "credential.helper=", "ls-remote", "--tags", source["git"],
                 "refs/tags/" + source["tag"], "refs/tags/" + source["tag"] + "^{}"],
                timeout=120, outcome="blocked-input").strip()
            validate_tag_binding(tag, source["tag"], source["revision"])
            ref = self.private / "inputs" / (name.lower() + "-source")
            self.clone_exact(source["git"], source["revision"], ref, name.lower() + "-source")
            license_path = ref / "LICENSE"
            require(license_path.is_file() and "Permission is hereby granted" in license_path.read_text(errors="replace"),
                    f"{name} MIT license missing", "blocked-input")
            if name == "SDWebImage":
                require(file_sha256(ref / "Package.swift") == PACKAGE_MANIFEST_SHA256,
                        "SDWebImage Package.swift changed", "blocked-input")
            payload_root = ref / name
            require(payload_root.is_dir(), f"{name} source directory missing", "blocked-input")
            self.reference_payloads[name] = tree_snapshot(payload_root)
        return {"specs": evidence, "sourceCommits": {n: v["revision"] for n, v in PODSPEC_INPUTS.items()},
                "packageManifestSHA256": PACKAGE_MANIFEST_SHA256}

    def seed_specs_cache(self) -> dict[str, Any]:
        metadata = validate_specs_metadata()
        repo = self.cp_home / "repos" / "pkglift-zb-specs"
        repo.mkdir(parents=True)
        metadata_path = repo / SPECS_METADATA_PATH
        metadata_path.write_bytes(SPECS_METADATA_BYTES)
        require(metadata_path.is_file() and not metadata_path.is_symlink()
                and file_sha256(metadata_path) == SPECS_METADATA_SHA256,
                "generated CocoaPods Specs metadata changed", "blocked-input")
        for name, source in PODSPEC_INPUTS.items():
            path = repo / source["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(self.spec_bytes[name])
        self.execute("spec-cache-init", ["git", "-c", "init.templateDir=", "init", "--quiet", repo])
        self.execute("spec-cache-hooks", ["git", "-C", repo, "config", "core.hooksPath", "/dev/null"])
        self.execute("spec-cache-remote", ["git", "-C", repo, "remote", "add", "origin", SPECS_URL])
        self.execute("spec-cache-add", ["git", "-C", repo, "add", "Specs", SPECS_METADATA_PATH])
        self.execute("spec-cache-commit", ["git", "-C", repo, "-c", "user.name=PkgLift Qualification",
                                            "-c", "user.email=qualification@invalid", "commit", "--quiet", "-m", "Pinned reviewed specs"])
        return {"generated": True, "remoteURL": SPECS_URL, "specsCommit": SPECS_COMMIT,
                "metadata": metadata, "paths": {name: source["path"] for name, source in PODSPEC_INPUTS.items()}}

    def command_env(self) -> None:
        os.environ["CP_HOME_DIR"] = str(self.cp_home)
        os.environ["COCOAPODS_DISABLE_STATS"] = "true"

    def pbx_json(self, root: Path, label: str, project: str = PROJECT) -> dict[str, Any]:
        raw = self.execute(label, ["plutil", "-convert", "json", "-o", "-", root / project / "project.pbxproj"])
        try:
            return json.loads(raw)
        except ValueError as error:
            raise QualificationError("failed-safety", "invalid pbx JSON") from error

    def discover_scheme(self, root: Path, label: str) -> dict[str, Any]:
        before = tree_snapshot(root)
        index = self.git(root, ["ls-files", "--stage", "-z"])
        status = self.git(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        try:
            listing = self.execute(label, ["xcodebuild", "-list", "-json", "-workspace", root / WORKSPACE],
                                   expect_json=True, outcome="inconclusive-baseline")
        finally:
            evidence = self.record_source_mutation(root, label, before, index, status)
            self.scheme_discovery[label] = evidence
            require(not evidence["treeChanged"] and not evidence["indexChanged"]
                    and not evidence["statusChanged"] and not evidence["gitStatusDirty"],
                    "scheme discovery mutated source", "failed-safety")
        schemes = listing.get("workspace", {}).get("schemes", [])
        require(schemes.count(TARGET) == 1, "existing hosted scheme is missing or ambiguous", "inconclusive-baseline")
        return {"name": TARGET, "count": 1, "generated": False}

    def prepare_swiftpm_directories(self, root: Path) -> dict[str, Any]:
        """Reproduce only observed directories in the outer and app project workspaces."""
        before = tree_snapshot(root)
        existing_parents = {parent.as_posix()
                            for relative in SWIFTPM_SETUP_DIRECTORIES
                            for parent in Path(relative).parents
                            if parent != Path(".") and parent.as_posix() not in SWIFTPM_SETUP_DIRECTORIES}
        require(all(before.get(path, {}).get("kind") == "directory"
                    for path in existing_parents),
                "SwiftPM setup parent missing or symlinked", "blocked-input")
        require(all(path not in before for path in SWIFTPM_SETUP_DIRECTORIES),
                "SwiftPM setup path unexpectedly exists", "blocked-input")
        index = self.git(root, ["ls-files", "--stage", "-z"])
        require(not self.git(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]),
                "SwiftPM setup source is dirty", "failed-safety")
        for relative in SWIFTPM_SETUP_DIRECTORIES:
            path = root / relative
            path.mkdir()  # No parents/exist_ok: never adopt an existing entry.
            path.chmod(SWIFTPM_SETUP_MODE)  # Exact observed mode, independent of umask.
        after = tree_snapshot(root)
        require(changed_paths(before, after) == list(SWIFTPM_SETUP_DIRECTORIES)
                and all(after[path] == {"kind": "directory", "mode": SWIFTPM_SETUP_MODE}
                        for path in SWIFTPM_SETUP_DIRECTORIES),
                "SwiftPM setup changed more than the reviewed directories", "failed-safety")
        require(self.git(root, ["ls-files", "--stage", "-z"]) == index
                and not self.git(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]),
                "SwiftPM setup changed Git state", "failed-safety")
        return {"paths": list(SWIFTPM_SETUP_DIRECTORIES), "mode": SWIFTPM_SETUP_MODE,
                "noFilesCreated": True, "beforeTreeSHA256": tree_digest(before),
                "afterTreeSHA256": tree_digest(after), "indexUnchanged": True, "worktreeClean": True}

    def prepare_portable_scheme(self, root: Path, label: str) -> dict[str, Any]:
        before = tree_snapshot(root)
        source = root / SCHEME_SOURCE
        destination = root / SCHEME_DESTINATION
        require(source.is_file() and not source.is_symlink() and file_sha256(source) == SCHEME_SHA256,
                "reviewed scheme source changed", "blocked-input")
        raw = source.read_bytes()
        validate_scheme_bytes(raw)
        require(not destination.exists(), "shared scheme unexpectedly exists", "blocked-input")
        destination.parent.mkdir(parents=True)
        destination.write_bytes(raw)
        require(file_sha256(destination) == SCHEME_SHA256 and destination.read_bytes() == raw,
                "portable scheme projection changed bytes", "failed-safety")
        changes = changed_paths(before, tree_snapshot(root))
        expected = [f"{PROJECT}/xcshareddata", f"{PROJECT}/xcshareddata/xcschemes", SCHEME_DESTINATION]
        require(changes == expected, "scheme preparation changed unexpected paths", "failed-safety")
        self.execute(label + "-add", ["git", "-C", root, "add", "--", SCHEME_DESTINATION])
        self.execute(label + "-commit", ["git", "-C", root, "-c", "user.name=PkgLift Qualification",
            "-c", "user.email=qualification@invalid", "commit", "--quiet", "-m", "Project reviewed upstream scheme"])
        require(not self.git(root, ["status", "--porcelain", "--untracked-files=all"]),
                "scheme-prepared source is dirty", "failed-safety")
        return {"source": SCHEME_SOURCE, "destination": SCHEME_DESTINATION, "sha256": SCHEME_SHA256,
                "byteIdentical": True, "inventedActions": False, "setupCommit": self.git(root, ["rev-parse", "HEAD"]).strip(),
                "tree": self.git(root, ["rev-parse", "HEAD^{tree}"]).strip()}

    def record_source_mutation(self, root: Path, label: str, before: Mapping[str, Any],
                               index: str, status_before: str) -> dict[str, Any]:
        after = tree_snapshot(root)
        index_after = self.git(root, ["ls-files", "--stage", "-z"])
        status = self.git(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        evidence = source_mutation_evidence(before, after, index, index_after, status, status_before)
        self.source_mutation_checks[label] = evidence
        return evidence

    def settings(self, root: Path, label: str, pods: set[str], package_context: Mapping[str, Any] | None = None) -> dict[str, str]:
        if label == "final":
            require(package_context is not None, "final settings require verified package resolution inputs", "blocked-input")
            self.validate_package_resolution_context(root, Path(package_context["derived"]))
        result = {}
        group_before = tree_snapshot(root)
        group_index = self.git(root, ["ls-files", "--stage", "-z"])
        group_status = self.git(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        try:
            for project, targets in [(root / PROJECT, {TARGET, *SIBLINGS}), (root / "Pods/Pods.xcodeproj", pods)]:
                for target in sorted(targets):
                    probe = f"{label}-{target}-settings"
                    before = tree_snapshot(root)
                    index = self.git(root, ["ls-files", "--stage", "-z"])
                    status = self.git(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
                    try:
                        command = ["xcodebuild", "-project", project, "-target", target,
                            "-configuration", "Debug", "-sdk", "iphonesimulator", "-showBuildSettings", "-json",
                            "CODE_SIGNING_ALLOWED=NO", "IPHONEOS_DEPLOYMENT_TARGET=15.0"]
                        if label == "final" and project == root / PROJECT:
                            derived = Path(package_context["derived"])
                            command.extend(["-clonedSourcePackagesDirPath", derived / "SourcePackages",
                                            "-onlyUsePackageVersionsFromResolvedFile", "-disableAutomaticPackageResolution",
                                            "-skipPackageUpdates"])
                        document = self.execute(probe, command, expect_json=True,
                            outcome="inconclusive-baseline" if label.startswith("baseline") else "failed-migration")
                    finally:
                        evidence = self.record_source_mutation(root, probe, before, index, status)
                        if label == "final" and project == root / PROJECT:
                            self.validate_package_resolution_context(root, Path(package_context["derived"]))
                        require(not evidence["treeChanged"] and not evidence["indexChanged"] and not evidence["statusChanged"],
                                f"{probe} changed source or Git state", "failed-safety")
                    result.update(validate_effective_settings(document, {target}))
        finally:
            evidence = self.record_source_mutation(root, label + "-settings-group", group_before, group_index, group_status)
            if label == "final":
                self.validate_package_resolution_context(root, Path(package_context["derived"]))
            require(not evidence["treeChanged"] and not evidence["indexChanged"] and not evidence["statusChanged"],
                    f"{label} settings changed source or Git state", "failed-safety")
        return result

    def build(self, root: Path, derived: Path, label: str, outcome: str,
              package_context: Mapping[str, Any] | None = None) -> dict[str, Any]:
        if label == "final-build":
            require(package_context is not None, "final build requires verified package resolution inputs", "blocked-input")
            self.validate_package_resolution_context(root, derived)
        before = tree_snapshot(root)
        index = self.git(root, ["ls-files", "--stage", "-z"])
        status = self.git(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        try:
            command = ["xcodebuild", "-workspace", root / WORKSPACE, "-scheme", TARGET,
                "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
                "-derivedDataPath", derived, "-clonedSourcePackagesDirPath", derived / "SourcePackages",
                "-onlyUsePackageVersionsFromResolvedFile", "-disableAutomaticPackageResolution",
                "-jobs", self.jobs, "CODE_SIGNING_ALLOWED=NO",
                "IPHONEOS_DEPLOYMENT_TARGET=15.0", "SYMROOT=" + str(derived / "Build/Products"),
                "OBJROOT=" + str(derived / "Build/Intermediates.noindex"),
                "SHARED_PRECOMPS_DIR=" + str(derived / "Build/Intermediates.noindex/PrecompiledHeaders"),
                "build-for-testing"]
            if label == "final-build": command.insert(-1, "-skipPackageUpdates")
            self.execute(label, command, timeout=1800, outcome=outcome)
        finally:
            evidence = self.record_source_mutation(root, label, before, index, status)
            if label == "final-build": self.validate_package_resolution_context(root, derived)
            require(not evidence["treeChanged"] and not evidence["indexChanged"] and not evidence["statusChanged"],
                    f"{label} changed source or Git state", "failed-safety")
        products = {name: [str(p.relative_to(derived)) for p in derived.rglob(name)]
                    for name in ("ZBNetworkingDemo.app", "ZBNetworkingDemoTests.xctest", "ZBNetworkingDemoUITests.xctest")}
        require(all(values for values in products.values()), "build-for-testing did not produce all app/test products", outcome)
        return {"commandMode": "build-for-testing", "deploymentTarget": "15.0", "products": products}

    def validate_pod_payload(self, root: Path, names: set[str]) -> dict[str, Any]:
        result = {}
        for name in names:
            installed = root / "Pods" / name / name
            require(installed.is_dir(), f"installed {name} payload missing", "blocked-input")
            current = tree_snapshot(installed)
            reference = self.reference_payloads[name]
            material = {path: item for path, item in current.items() if item["kind"] != "directory"}
            for relative, item in material.items():
                require(reference.get(relative) == item,
                        f"{name} installed payload differs from reviewed source at {relative}", "blocked-input")
            selected = {path: item for path, item in material.items() if Path(path).suffix in {".h", ".m"}}
            require(selected, f"{name} selected source closure is empty", "blocked-input")
            result[name] = {"installedMaterialEntries": len(material), "selectedSourceEntries": len(selected),
                            "selectedSourceTreeSHA256": tree_digest(selected),
                            "excludedReferenceEntries": len([p for p, item in reference.items()
                                                             if item["kind"] != "directory" and p not in material])}
        return result

    def validate_retained_af_locked_payload(self, root: Path) -> dict[str, Any]:
        """Accept only CocoaPods' reviewed owner-write-bit removal on AF sources."""
        reference = self.reference_payloads["AFNetworking"]
        reviewed_digest = tree_digest(reference)
        require(len(reference) == RETAINED_AF_FILE_COUNT
                and all(item["kind"] == "file" and Path(path).suffix in {".h", ".m"}
                        for path, item in reference.items())
                and sum(item["mode"] == 0o644 for item in reference.values()) == 13
                and sum(item["mode"] == 0o755 for item in reference.values()) == 1
                and reviewed_digest == RETAINED_AF_REVIEWED_SOURCE_TREE_SHA256,
                "reviewed AFNetworking payload changed", "blocked-input")
        expected = copy.deepcopy(reference)
        transitions: dict[str, int] = {}
        for item in expected.values():
            before = item["mode"]
            item["mode"] = before & ~RETAINED_AF_REMOVE_MODE_BITS
            transition = f"{before:04o}->{item['mode']:04o}"
            transitions[transition] = transitions.get(transition, 0) + 1
        expected_digest = tree_digest(expected)
        require(expected_digest == RETAINED_AF_EXPECTED_LOCKED_TREE_SHA256,
                "expected AFNetworking locked payload changed", "blocked-input")
        installed = root / "Pods" / "AFNetworking" / "AFNetworking"
        require(all(path.is_dir() and not path.is_symlink()
                    for path in (root / "Pods", root / "Pods" / "AFNetworking", installed)),
                "installed AFNetworking payload path contains a symlink", "blocked-input")
        actual = tree_snapshot(installed)
        require(actual == expected,
                "installed AFNetworking payload differs from exact locked reviewed payload", "blocked-input")
        return {"selectedSourceEntries": RETAINED_AF_FILE_COUNT,
                "selectedSourceTreeSHA256": tree_digest(actual),
                "reviewedSourceTreeSHA256": reviewed_digest,
                "expectedLockedTreeSHA256": expected_digest,
                "modePolicy": RETAINED_AF_LOCK_MODE_POLICY,
                "modeTransitions": transitions}

    def validate_package_resolution_locks(self, root: Path) -> None:
        paths = [root / relative for relative in PACKAGE_RESOLVED_PATHS]
        require({str(path.relative_to(root)) for path in root.rglob("Package.resolved")
                 if ".git" not in path.parts} == set(PACKAGE_RESOLVED_PATHS),
                "Package.resolved inventory changed", "failed-safety")
        for path in paths:
            parents = [root / Path(*Path(path.relative_to(root)).parts[:index])
                       for index in range(1, len(Path(path.relative_to(root)).parts))]
            require(all(parent.is_dir() and not parent.is_symlink() for parent in parents)
                    and path.is_file() and not path.is_symlink() and (path.stat().st_mode & 0o777) == 0o644
                    and path.read_bytes() == PACKAGE_RESOLVED_BYTES and file_sha256(path) == PACKAGE_RESOLVED_SHA256,
                    "reviewed Package.resolved changed", "failed-safety")

    def validate_package_checkout_paths(self, derived: Path) -> Path:
        checkout = derived / "SourcePackages/checkouts/SDWebImage"
        for path in (derived, derived / "SourcePackages", derived / "SourcePackages/checkouts", checkout):
            if path.exists() or path.is_symlink():
                require(path.is_dir() and not path.is_symlink(),
                        "package checkout path is not a real directory", "failed-safety")
        return checkout

    def validate_package_resolution_context(self, root: Path, derived: Path) -> dict[str, Any]:
        self.validate_package_resolution_locks(root)
        checkout = self.validate_package_checkout_paths(derived)
        try:
            require(checkout.is_dir()
                    and self.git(checkout, ["rev-parse", "HEAD"]).strip() == PACKAGE_REVISION
                    and not self.git(checkout, ["status", "--porcelain", "--untracked-files=all"])
                    and file_sha256(checkout / "Package.swift") == PACKAGE_MANIFEST_SHA256,
                    "resolved checkout differs from reviewed source", "failed-safety")
        except (QualificationError, OSError) as error:
            raise QualificationError("failed-safety", "resolved checkout differs from reviewed source") from error
        return {"paths": list(PACKAGE_RESOLVED_PATHS), "rawSHA256": PACKAGE_RESOLVED_SHA256,
                "derived": str(derived), "checkoutRevision": PACKAGE_REVISION,
                "manifestSHA256": PACKAGE_MANIFEST_SHA256}

    def prepare_package_resolution_inputs(self, root: Path) -> dict[str, Any]:
        paths = [root / relative for relative in PACKAGE_RESOLVED_PATHS]
        require(sha256_bytes(PACKAGE_RESOLVED_BYTES) == PACKAGE_RESOLVED_SHA256,
                "reviewed Package.resolved bytes changed", "blocked-input")
        for path in paths:
            parents = [root / Path(*Path(path.relative_to(root)).parts[:index])
                       for index in range(1, len(Path(path.relative_to(root)).parts))]
            require(all(parent.is_dir() and not parent.is_symlink() for parent in parents)
                    and not path.exists() and not path.is_symlink(),
                    "Package.resolved input path is unavailable", "blocked-input")
        before, index = tree_snapshot(root), self.git(root, ["ls-files", "--stage", "-z"])
        status = self.git(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        before_records = sorted(filter(None, status.split("\0")))
        require(all(len(record) >= 4 and record[2] == " " and not set(record[:2]) & {"R", "C"}
                    for record in before_records),
                "package input preparation does not accept rename/copy status records", "blocked-input")
        for path in paths:
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
            try:
                os.write(descriptor, PACKAGE_RESOLVED_BYTES)
            finally:
                os.close(descriptor)
            os.chmod(path, 0o644)
        after = tree_snapshot(root)
        index_after = self.git(root, ["ls-files", "--stage", "-z"])
        status_after = self.git(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        expected_status_added = "?? " + PACKAGE_RESOLVED_PATHS[0]
        after_records = sorted(filter(None, status_after.split("\0")))
        require(changed_paths(before, after) == sorted(PACKAGE_RESOLVED_PATHS)
                and all(after[relative] == {"kind": "file", "mode": 0o644, "size": len(PACKAGE_RESOLVED_BYTES),
                                             "sha256": PACKAGE_RESOLVED_SHA256}
                        for relative in PACKAGE_RESOLVED_PATHS)
                and index_after == index
                and expected_status_added not in before_records
                and after_records == sorted([*before_records, expected_status_added]),
                "Package.resolved preparation changed unexpected source or Git state", "failed-safety")
        return {"paths": list(PACKAGE_RESOLVED_PATHS), "rawSHA256": PACKAGE_RESOLVED_SHA256,
                "mode": 0o644, "treeSHA256": tree_digest(after), "expectedStatusAdded": expected_status_added,
                "beforeIndexSHA256": sha256_bytes(index.encode()), "afterIndexSHA256": sha256_bytes(index_after.encode()),
                "beforeStatusSHA256": sha256_bytes(status.encode()), "afterStatusSHA256": sha256_bytes(status_after.encode())}

    def resolve_reviewed_package(self, root: Path, derived: Path) -> dict[str, Any]:
        self.validate_package_resolution_locks(root)
        self.validate_package_checkout_paths(derived)
        before, index = tree_snapshot(root), self.git(root, ["ls-files", "--stage", "-z"])
        status = self.git(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        command_error: QualificationError | None = None
        try:
            self.execute("resolve-reviewed-package", ["xcodebuild", "-resolvePackageDependencies",
                "-workspace", root / WORKSPACE, "-scheme", TARGET, "-derivedDataPath", derived,
                "-clonedSourcePackagesDirPath", derived / "SourcePackages",
                "-onlyUsePackageVersionsFromResolvedFile", "-disableAutomaticPackageResolution", "-skipPackageUpdates"],
                timeout=900, outcome="failed-migration")
        except QualificationError as error:
            command_error = error
        finally:
            evidence = self.record_source_mutation(root, "resolve-reviewed-package", before, index, status)
            self.validate_package_resolution_locks(root)
            checkout = self.validate_package_checkout_paths(derived)
            if checkout.exists(): self.validate_package_resolution_context(root, derived)
            require(not evidence["treeChanged"] and not evidence["indexChanged"] and not evidence["statusChanged"],
                    "resolve-reviewed-package changed source or Git state", "failed-safety")
        if command_error is not None: raise command_error
        context = self.validate_package_resolution_context(root, derived)
        return context

    def post_install(self, root: Path) -> dict[str, Any]:
        profile = "(version 1)(allow default)(deny network*)"
        self.execute("post-migration-pod-install", ["/usr/bin/sandbox-exec", "-p", profile,
            "pod", "install", "--no-repo-update", "--no-ansi"], cwd=root, timeout=900, outcome="failed-migration")
        lock = (root / "Podfile.lock").read_text()
        validated = validate_lock(lock, {"AFNetworking"})
        require((root / "Pods/Manifest.lock").read_text() == lock, "final manifest differs from lock")
        which = self.execute("retained-af-podspec", ["/usr/bin/sandbox-exec", "-p", profile, "pod", "spec", "which",
            "AFNetworking", "--version=4.0.1", "--no-ansi"], cwd=root, timeout=60, outcome="blocked-input").strip()
        path = Path(which).resolve(strict=True)
        cache = (self.cp_home / "repos" / "pkglift-zb-specs").resolve(strict=True)
        require(path.is_relative_to(cache) and file_sha256(path) == PODSPEC_INPUTS["AFNetworking"]["rawSHA256"],
                "retained podspec did not resolve from reviewed cache", "blocked-input")
        project_text = (root / "Pods/Pods.xcodeproj/project.pbxproj").read_text()
        require("PBXShellScriptBuildPhase" not in project_text, "Pods project gained a shell phase", "blocked-input")
        return {"lock": validated, "podspecPath": PODSPEC_INPUTS["AFNetworking"]["path"],
                "payload": {"AFNetworking": self.validate_retained_af_locked_payload(root)}}

    def run(self, contract: Mapping[str, Any]) -> dict[str, Any]:
        self.output.mkdir(); self.private.mkdir(); self.report.mkdir(); self.command_env()
        summary: dict[str, Any] = {"schemaVersion": 1, "case": "zbnetworking-multitarget",
            "status": "failed-safety", "source": {"repository": REPOSITORY, "commit": SOURCE_COMMIT, "license": SOURCE_LICENSE},
            "selection": {"project": PROJECT, "workspace": WORKSPACE, "scheme": TARGET}, "artifact": contract["artifact"],
            "claims": {"compileOnly": True, "deploymentTarget": "15.0", "testsExecuted": False, "appLaunched": False},
            "implementation": {"runnerSHA256": file_sha256(Path(__file__)), "sharedRunnerSHA256": file_sha256(AWS_PATH),
                               "executionIntakeSHA256": INTAKE_SHA256}}
        try:
            summary["executionIntake"] = validate_execution_intake()
            summary["environment"] = self.environment_gate()
            require(Path("/usr/bin/sandbox-exec").is_file(), "sandbox-exec unavailable", "blocked-input")
            summary["dependencyIntake"] = self.fetch_inputs()
            summary["specsCache"] = self.seed_specs_cache()
            baseline, migration = self.private / "baseline-source", self.private / "migration-source"
            summary["baselineSource"] = self.clone_source(baseline, "baseline")
            summary["migrationSource"] = self.clone_source(migration, "migration")
            summary["baselineSchemePreparation"] = self.prepare_portable_scheme(baseline, "baseline-scheme-prepare")
            summary["migrationSchemePreparation"] = self.prepare_portable_scheme(migration, "migration-scheme-prepare")
            require(summary["baselineSchemePreparation"]["tree"] == summary["migrationSchemePreparation"]["tree"],
                    "baseline and migration scheme setup trees differ", "failed-safety")
            summary["baselineDirectoryPreparation"] = self.prepare_swiftpm_directories(baseline)
            summary["migrationDirectoryPreparation"] = self.prepare_swiftpm_directories(migration)
            require(summary["baselineDirectoryPreparation"] == summary["migrationDirectoryPreparation"],
                    "baseline and migration directory setup evidence differs", "failed-safety")
            summary["baselineScheme"] = self.discover_scheme(baseline, "baseline-scheme-list")
            self.discover_scheme(migration, "migration-scheme-list")
            summary["baselinePayload"] = self.validate_pod_payload(baseline, set(POD_VERSIONS))
            baseline_payload = summary["baselinePayload"]
            baseline_project = self.pbx_json(baseline, "baseline-project")
            baseline_pods_project = self.pbx_json(baseline, "baseline-pods-project", "Pods/Pods.xcodeproj")
            summary["baselineExecutionInputs"] = validate_build_execution_inputs(
                baseline_project, baseline_pods_project, {"Pods-ZBNetworkingDemo", *POD_VERSIONS})
            summary["baselineHeaderLinks"] = validate_header_links(baseline, set(POD_VERSIONS))
            baseline_siblings = sibling_closure(baseline_project)
            baseline_protected = shared.protected_project_state(baseline_project)
            baseline_zb_protected = zb_protected_project_state(baseline_project)
            baseline_checkpoint = tree_snapshot(baseline)
            baseline_index = self.git(baseline, ["ls-files", "--stage", "-z"])
            baseline_status = self.git(baseline, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
            require(not baseline_status
                    and tree_digest(baseline_checkpoint) == summary["baselineDirectoryPreparation"]["afterTreeSHA256"],
                    "baseline differs from the clean prepared source before probes", "failed-safety")
            try:
                summary["baselineSettings"] = self.settings(baseline, "baseline", {"Pods-ZBNetworkingDemo", *POD_VERSIONS})
                summary["baselineBuild"] = self.build(baseline, self.private / "baseline-derived", "baseline-build", "inconclusive-baseline")
            finally:
                evidence = self.record_source_mutation(baseline, "baseline-probes-build", baseline_checkpoint,
                                                       baseline_index, baseline_status)
                require(not evidence["treeChanged"] and not evidence["indexChanged"]
                        and not evidence["statusChanged"] and not evidence["gitStatusDirty"],
                        "baseline probes/build changed prepared source", "failed-safety")
            original = tree_snapshot(migration)
            original_podfile = (migration / "Podfile").read_bytes()
            exclude_generated_plan(migration, ".pkglift/plan.json")
            common = ["--path", migration, "--project", PROJECT, "--workspace", WORKSPACE, "--no-color"]
            analysis = self.execute("analysis", [self.binary, "analyze", *common, "--json"], expect_json=True)
            portable_analysis = self.execute("analysis-portable", [self.binary, "analyze", *common, "--portable-json"], expect_json=True)
            plan_stdout = self.execute("plan", [self.binary, "plan", *common, "--json"], expect_json=True)
            plan_path = migration / ".pkglift/plan.json"
            require(plan_path.is_file() and json.loads(plan_path.read_text()) == plan_stdout, "saved plan differs from stdout")
            portable_plan = self.execute("plan-portable", [self.binary, "plan", *common, "--portable-json"], expect_json=True)
            plan = json.loads(plan_path.read_text())
            summary["plan"] = validate_analysis_and_plan(analysis, plan, migration)
            require(portable_plan.get("schemaVersion") == plan["schemaVersion"],
                    "portable plan lost its execution schema boundary")
            validate_portable_parity(analysis, portable_analysis, "candidates")
            validate_portable_parity(plan, portable_plan, "entries")
            (self.report / "portable-analysis.json").write_text(json.dumps(shared.redact(portable_analysis, self.redaction_roots), indent=2, sort_keys=True) + "\n")
            (self.report / "portable-plan.json").write_text(json.dumps(shared.redact(portable_plan, self.redaction_roots), indent=2, sort_keys=True) + "\n")
            require(not self.git(migration, ["status", "--porcelain", "--untracked-files=all"]), "planning dirtied source")
            index = self.git(migration, ["ls-files", "--stage", "-z"]); before_dry = tree_snapshot(migration)
            dry = self.execute("migration-dry-run", [self.binary, "migrate", *common])
            validate_dry_run_output(dry); validate_dry_run(before_dry, tree_snapshot(migration))
            require(self.git(migration, ["ls-files", "--stage", "-z"]) == index
                    and not self.git(migration, ["status", "--porcelain", "--untracked-files=all"]), "dry run changed Git state")
            self.execute("migration-apply", [self.binary, "migrate", *common, "--apply"])
            post_apply = self.pbx_json(migration, "post-apply-project")
            require(sibling_closure(post_apply) == baseline_siblings, "PkgLift changed sibling target closure")
            require(shared.protected_project_state(post_apply) == baseline_protected,
                    "PkgLift changed protected source/resource/settings state")
            validate_linkage(post_apply)
            require(zb_protected_project_state(post_apply) == baseline_zb_protected,
                    "PkgLift changed protected framework/dependency/project metadata")
            declaration = b"pod 'SDWebImage'\n"
            require(original_podfile.count(declaration) == 1
                    and original_podfile.replace(declaration, b"") == (migration / "Podfile").read_bytes(),
                    "Podfile changed beyond exact SDWebImage removal")
            apply_tree = tree_snapshot(migration)
            allowed_apply = {"Podfile", f"{PROJECT}/project.pbxproj"}
            bad_apply = [path for path in changed_paths(original, apply_tree)
                         if path not in allowed_apply and path != ".pkglift" and not path.startswith(".pkglift/")]
            require(not bad_apply, "unexpected apply delta: " + ", ".join(bad_apply[:10]))
            summary["cocoaPodsRefresh"] = self.post_install(migration)
            require(summary["cocoaPodsRefresh"]["payload"]["AFNetworking"]["reviewedSourceTreeSHA256"]
                    == baseline_payload["AFNetworking"]["selectedSourceTreeSHA256"]
                    and summary["cocoaPodsRefresh"]["payload"]["AFNetworking"]["selectedSourceEntries"]
                    == baseline_payload["AFNetworking"]["selectedSourceEntries"],
                    "retained AFNetworking selected source closure changed")
            final_project = self.pbx_json(migration, "final-project")
            final_pods_project = self.pbx_json(migration, "final-pods-project", "Pods/Pods.xcodeproj")
            summary["finalExecutionInputs"] = validate_build_execution_inputs(
                final_project, final_pods_project, {"Pods-ZBNetworkingDemo", "AFNetworking"})
            summary["finalHeaderLinks"] = validate_header_links(migration, {"AFNetworking"})
            require(sibling_closure(final_project) == baseline_siblings, "CocoaPods changed sibling target closure")
            require(shared.protected_project_state(final_project) == baseline_protected,
                    "CocoaPods refresh changed protected source/resource/settings state")
            summary["linkage"] = validate_linkage(final_project)
            require(zb_protected_project_state(final_project) == baseline_zb_protected,
                    "CocoaPods refresh changed protected framework/dependency/project metadata")
            verify = self.execute("structural-verification", [self.binary, "verify", *common, "--json"], expect_json=True)
            require(verify.get("checks") and all(x.get("passed") is True for x in verify["checks"]), "structural verification failed")
            (self.report / "structural-verification.json").write_text(json.dumps(shared.redact(verify, self.redaction_roots), indent=2, sort_keys=True) + "\n")
            final_derived = self.private / "final-derived"
            summary["packageResolutionInputs"] = self.prepare_package_resolution_inputs(migration)
            summary["resolved"] = self.resolve_reviewed_package(migration, final_derived)
            summary["finalSettings"] = self.settings(migration, "final", {"Pods-ZBNetworkingDemo", "AFNetworking"},
                                                       summary["resolved"])
            summary["resolvedAfterSettings"] = self.validate_package_resolution_context(migration, final_derived)
            summary["finalBuild"] = self.build(migration, final_derived, "final-build", "failed-migration", summary["resolved"])
            summary["resolvedAfterBuild"] = self.validate_package_resolution_context(migration, final_derived)
            summary["finalChangedPaths"] = validate_final_delta(original, tree_snapshot(migration))
            require(file_sha256(migration / SCHEME_DESTINATION) == SCHEME_SHA256
                    and all(validate_scheme_bytes((migration / path).read_bytes()) for path in
                            [SCHEME_SOURCE, SCHEME_DESTINATION]), "reviewed scheme bytes changed")
            summary["status"] = "passed-migration"
        except QualificationError as error:
            summary["status"] = error.outcome; summary["failure"] = str(error); raise
        except Exception as error:
            summary["status"] = "failed-safety"; summary["failure"] = f"unexpected runner error: {type(error).__name__}"
            raise QualificationError("failed-safety", summary["failure"]) from error
        finally:
            summary["commands"] = self.commands
            summary["schemeDiscovery"] = self.scheme_discovery
            summary["sourceMutationChecks"] = self.source_mutation_checks
            if self.final_build_diagnostic is not None:
                summary["finalBuildDiagnostic"] = self.final_build_diagnostic
            portable = shared.redact(summary, self.redaction_roots)
            for command in portable.get("commands", []):
                command.pop("redactedStderrTail", None)
                command.pop("redactedStdoutTail", None)
            (self.report / "summary.json").write_text(json.dumps(portable, indent=2, sort_keys=True) + "\n")
        return summary


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pkglift", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--jobs", type=int, default=2, choices=range(1, 5), metavar="1..4")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        contract = validate_runtime_contract(args.pkglift, args.output, os.environ)
    except QualificationError as error:
        print(f"blocked before execution: {error}", file=sys.stderr); return 2
    runner = Runner(contract, args.jobs)
    try:
        runner.run(contract)
    except QualificationError as error:
        print(f"qualification outcome {error.outcome}: {error}", file=sys.stderr); return 1
    print(json.dumps({"status": "passed-migration", "report": str(args.output / "report")}, indent=2)); return 0


if __name__ == "__main__":
    raise SystemExit(main())
