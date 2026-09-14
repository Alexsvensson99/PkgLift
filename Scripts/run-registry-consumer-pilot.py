#!/usr/bin/env python3
"""Build pinned repository-owned consumers before admitting registry mappings."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

CASES = {
    "KeychainAccess": {
        "version": "4.2.2", "repository": "https://github.com/kishikawakatsumi/KeychainAccess",
        "revision": "84e546727d66f1adc5439debad16270d0fdd04e7",
        "source": "Lib/KeychainAccess/Keychain.swift",
        "sourceSHA256": "643188af53d8dbecddd3de1a6e6888ea801d1bc4f022138a4a56a6aea0e7a274",
        "specURL": "https://cdn.cocoapods.org/Specs/f/6/3/KeychainAccess/4.2.2/KeychainAccess.podspec.json",
        "specSHA256": "4ce03eee844a5d98600f81b6284cb17968005d0504e4a7a5b86ad4f4e87cbc48",
    },
    "DeviceKit": {
        "version": "5.8.0", "repository": "https://github.com/devicekit/DeviceKit",
        "revision": "56b997e8a61707218f9af09f32b2a1d1806fd792",
        "source": "Source/Device.generated.swift",
        "sourceSHA256": "025d97e3d3071b1b7a080a4ed6b22d342a57aa872454a8ad389b51f8c27b3ad5",
        "specURL": "https://cdn.cocoapods.org/Specs/d/e/6/DeviceKit/5.8.0/DeviceKit.podspec.json",
        "specSHA256": "87970b1f51a445b9d1e22b4cca1f8c2a7b70bafbb4ed8cd46d2c98691cfa43a8",
    },
}
PRIVACY = {
    "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [],
    "NSPrivacyTracking": False,
    "NSPrivacyAccessedAPITypes": [{
        "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryDiskSpace",
        "NSPrivacyAccessedAPITypeReasons": ["85F4.1", "E174.1"],
    }],
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_state(root):
    result = []
    for path in sorted(root.rglob("*")):
        name = str(path.relative_to(root))
        if path.is_symlink():
            result.append((name, "symlink", os.readlink(path)))
        elif path.is_file():
            result.append((name, path.stat().st_mode, digest(path)))
        elif path.is_dir():
            result.append((name, "directory", path.stat().st_mode))
        else:
            raise RuntimeError(f"Unexpected fixture entry: {name}")
    return hashlib.sha256(canonical(result)).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=CASES, required=True)
    parser.add_argument("--phase", choices=["equivalence", "migration"], required=True)
    args = parser.parse_args()
    case = CASES[args.case]
    repo = Path(os.environ["GITHUB_WORKSPACE"]).resolve(strict=True)
    root = Path(tempfile.mkdtemp(prefix=f"pkglift-registry-{args.case}-", dir=os.environ["RUNNER_TEMP"]))
    reports = root / "report"
    reports.mkdir()
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as handle:
        handle.write(f"REGISTRY_REPORT_DIR={reports}\n")
    summary = {"case": args.case, "phase": args.phase, "platform": "iOS", "deploymentTarget": "15.0",
               "consumerLanguages": ["swift"], "status": "incomplete", "sourceRevision": case["revision"]}

    def run(label, command, cwd=None, seconds=1200, json_output=False):
        output = reports / (label + (".json" if json_output else ".log"))
        wrapper = [sys.executable, str(repo / "Scripts/run-with-timeout.py"), "--seconds", str(seconds)]
        if json_output:
            wrapper += ["--stdout", str(output), "--stderr", str(reports / (label + ".stderr.log"))]
        else:
            wrapper += ["--combined-log", str(output)]
        if cwd:
            wrapper += ["--cwd", str(cwd)]
        print(f"{args.case}: {label}", flush=True)
        subprocess.run(wrapper + ["--"] + [str(value) for value in command], check=True)
        return output

    def source_check(directory):
        require(digest(directory / case["source"]) == case["sourceSHA256"], "Resolved source bytes changed")
        if args.case == "DeviceKit":
            require(plistlib.loads((directory / "Source/PrivacyInfo.xcprivacy").read_bytes()) == PRIVACY,
                    "Resolved privacy manifest changed")

    def privacy_check(directory):
        if args.case != "DeviceKit":
            return []
        paths = sorted(directory.rglob("PrivacyInfo.xcprivacy"))
        require(bool(paths), "The built consumer lost the DeviceKit privacy manifest")
        for path in paths:
            require(plistlib.loads(path.read_bytes()) == PRIVACY, "Built privacy manifest semantics changed")
        return [str(path.relative_to(directory)) for path in paths]

    def lock_check(directory):
        lock = (directory / "Podfile.lock").read_text()
        require(re.search(r"^  - " + re.escape(args.case) + r" \(" + re.escape(case["version"]) + r"\)",
                          lock, re.MULTILINE), "CocoaPods did not resolve the exact pinned version")
        local = json.loads((directory / f"Pods/Local Podspecs/{args.case}.podspec.json").read_text())
        for field in ["name", "version", "source", "source_files", "platforms", "resource_bundles",
                      "dependencies", "prepare_command", "script_phases", "exclude_files", "vendored_frameworks"]:
            require(local.get(field) == spec.get(field), f"Installed podspec changed field {field}")
        source_check(directory / "Pods" / args.case)

    def pins_check(path):
        document = json.loads(path.read_text())
        pins = document.get("pins", document.get("object", {}).get("pins", []))
        matches = [pin for pin in pins if pin.get("identity", pin.get("package", "")).lower() == args.case.lower()]
        require(len(matches) == 1, "Missing or ambiguous SwiftPM pin")
        pin = matches[0]
        require(pin["state"]["version"] == case["version"] and pin["state"]["revision"] == case["revision"],
                "SwiftPM version or source revision differs from reviewed source")
        require(pin.get("location", pin.get("repositoryURL", "")).removesuffix(".git").lower()
                == case["repository"].lower(), "SwiftPM repository differs from reviewed source")

    try:
        for command in ["pod", "xcodebuild"]:
            require(shutil.which(command), f"Missing required tool: {command}")
        fixture = repo / "Fixtures" / ("Swift" + args.case)
        require(fixture.is_dir() and not fixture.is_symlink() and repo in fixture.resolve().parents
                and not any(p.is_symlink() for p in fixture.rglob("*")), "Unsafe fixture")
        mapping_relative = Path(args.case[0]) / (args.case + ".yml")
        mapping_paths = [repo / "Registry" / mapping_relative,
                         repo / "Sources/PkgLiftRegistry/BundledRegistry" / mapping_relative]
        require(all(p.is_file() for p in mapping_paths) if args.phase == "migration"
                else not any(p.exists() for p in mapping_paths),
                "Equivalence must precede both registry entries; migration requires both entries")
        fixture_hash = tree_state(fixture)
        probe_hash = digest(fixture / "App/Consumer.swift")
        with urllib.request.urlopen(case["specURL"], timeout=30) as response:
            spec = json.load(response)
        require(hashlib.sha256(canonical(spec)).hexdigest() == case["specSHA256"], "Public podspec changed")
        (reports / "public-podspec.json").write_bytes(canonical(spec))
        run("environment-xcode", ["xcodebuild", "-version"], seconds=60)
        run("environment-pods", ["pod", "--version"], seconds=60)

        baseline = root / "baseline"
        shutil.copytree(fixture, baseline)
        target = "Swift" + args.case
        run("baseline-pod-install", ["pod", "install", "--clean-install"], baseline, seconds=600)
        lock_check(baseline)
        shutil.copyfile(baseline / "Podfile.lock", reports / "baseline-Podfile.lock")
        baseline_data = root / "baseline-derived"
        run("baseline-build", ["xcodebuild", "-workspace", baseline / (target + ".xcworkspace"),
            "-scheme", target, "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination",
            "generic/platform=iOS Simulator", "-derivedDataPath", baseline_data, "-jobs", "2",
            "CODE_SIGNING_ALLOWED=NO", "build"])
        source_check(baseline / "Pods" / args.case)
        summary["cocoaPodsBuild"] = "passed"
        summary["cocoaPodsPrivacy"] = privacy_check(baseline_data / "Build/Products/Debug-iphonesimulator" / (target + ".app"))

        spm = root / "swiftpm"
        (spm / "Sources/RegistryConsumer").mkdir(parents=True)
        shutil.copyfile(fixture / "App/Consumer.swift", spm / "Sources/RegistryConsumer/Consumer.swift")
        (spm / "Package.swift").write_text(
            '// swift-tools-version: 5.9\nimport PackageDescription\n'
            'let package = Package(name: "RegistryConsumer", platforms: [.iOS(.v15)], '
            'products: [.library(name: "RegistryConsumer", targets: ["RegistryConsumer"])], '
            f'dependencies: [.package(url: "{case["repository"]}", exact: "{case["version"]}")], '
            f'targets: [.target(name: "RegistryConsumer", dependencies: [.product(name: "{args.case}", '
            f'package: "{args.case}")])])\n')
        spm_data = root / "swiftpm-derived"
        packages = root / "swiftpm-packages"
        run("swiftpm-build", ["xcodebuild", "-scheme", "RegistryConsumer", "-configuration", "Debug",
            "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator", "-derivedDataPath",
            spm_data, "-clonedSourcePackagesDirPath", packages, "-jobs", "2", "CODE_SIGNING_ALLOWED=NO", "build"], spm)
        pins = list(spm.rglob("Package.resolved"))
        require(len(pins) == 1, "Missing or ambiguous SwiftPM resolution file")
        pins_check(pins[0])
        shutil.copyfile(pins[0], reports / "SwiftPM-Package.resolved")
        checkouts = [p for p in (packages / "checkouts").iterdir() if (p / case["source"]).is_file()]
        require(len(checkouts) == 1, "Missing or ambiguous package source checkout")
        source_check(checkouts[0])
        summary["swiftPMBuild"] = "passed"
        summary["swiftPMPrivacy"] = privacy_check(spm_data / "Build/Products/Debug-iphonesimulator")
        require(digest(baseline / "App/Consumer.swift") == digest(spm / "Sources/RegistryConsumer/Consumer.swift")
                == probe_hash, "The two integrations did not compile identical consumer source")

        if args.phase == "migration":
            binary = Path(os.environ["PKGLIFT_BIN"])
            migration = root / "migration"
            shutil.copytree(fixture, migration)
            run("migration-pod-install", ["pod", "install", "--clean-install"], migration, seconds=600)
            lock_check(migration)
            app_before = tree_state(migration / "App")
            common = ["--path", migration, "--project", target + ".xcodeproj", "--no-color"]
            analysis = json.loads(run("analysis", [binary, "analyze", *common, "--json"], json_output=True).read_text())
            run("plan-command", [binary, "plan", *common, "--json"], json_output=True)
            plan = json.loads((migration / ".pkglift/plan.json").read_text())
            shutil.copyfile(migration / ".pkglift/plan.json", reports / "plan.json")
            auto = [c for c in analysis["candidates"] if c["classification"] == "AUTO"]
            entries = [e for e in plan["entries"] if e["classification"] == "AUTO"]
            require(len(auto) == len(entries) == 1 and auto[0]["pod"]["name"] == entries[0]["podName"] == args.case,
                    "Reviewed AUTO set differs from the exact candidate")
            require(entries[0]["packageCandidate"]["products"] == [args.case], "Unexpected package product")
            require(entries[0]["packageCandidate"]["supportedConsumerLanguages"] == ["swift"], "Unproven consumer languages")
            require(entries[0]["targetSourceProfile"] == {"languages": ["swift"], "completeness": "complete"},
                    "Consumer target language evidence changed")
            dry_before = tree_state(migration)
            run("dry-run", [binary, "migrate", *common])
            require(tree_state(migration) == dry_before, "Dry run mutated the fixture")
            run("apply", [binary, "migrate", *common, "--apply"])
            require(args.case not in (migration / "Podfile").read_text(), "Migrated pod declaration remains")
            run("migrated-pod-install", ["pod", "install", "--clean-install"], migration, seconds=600)
            require(args.case not in (migration / "Podfile.lock").read_text(), "Migrated pod remains locked")
            migrated_data = root / "migrated-derived"
            run("verification", [binary, "verify", *common, "--workspace", target + ".xcworkspace", "--build",
                "--scheme", target, "--configuration", "Debug", "--sdk", "iphonesimulator", "--destination",
                "generic/platform=iOS Simulator", "--derived-data-path", migrated_data, "--json"], json_output=True)
            require(tree_state(migration / "App") == app_before, "Migration changed consumer sources")
            summary["migratedPrivacy"] = privacy_check(migrated_data / "Build/Products/Debug-iphonesimulator" / (target + ".app"))
            summary["migration"] = "passed"

        require(tree_state(fixture) == fixture_hash, "Repository-owned fixture changed")
        summary.update(status="passed", consumerSHA256=probe_hash, sourceSHA256=case["sourceSHA256"],
                       publicSpecSHA256=case["specSHA256"], repositoryFixtureUnchanged=True)
    finally:
        (reports / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(json.dumps(summary, indent=2), flush=True)
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as handle:
        handle.write(f"### {args.case}: {args.phase} passed\n\nSwift consumer, iOS 15, exact {case['version']}; source and privacy checks passed.\n")


if __name__ == "__main__":
    main()
