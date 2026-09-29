#!/usr/bin/env python3
"""Qualify an exact signed release candidate on an explicitly selected macOS host.

The package job supplies hashes after Developer ID/notarization checks. This
helper binds to those bytes and tests core CLI runtime, including structural
apply. Consumer compilation remains a separate, toolchain-specific release gate.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import platform
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.dont_write_bytecode = True

_SPEC = importlib.util.spec_from_file_location(
    "published_runtime", Path(__file__).with_name("verify-runtime-environment.py"))
if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError("Runtime validation helpers are unavailable")
shared = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(shared)
VerificationError = shared.VerificationError


def require(condition, message):
    if not condition:
        raise VerificationError(message)


def validate_identity(args):
    for name in ("archive_sha256", "binary_sha256"):
        require(re.fullmatch(r"[0-9a-f]{64}", getattr(args, name)) is not None,
                "Expected SHA-256 identities must contain 64 lowercase hexadecimal characters.")
    require(re.fullmatch(r"[0-9a-f]{40}", args.source_commit) is not None,
            "Expected source commit must be a full lowercase Git SHA.")
    require(re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", args.version) is not None,
            "Expected version must be a stable semantic version.")
    require(args.required_macos_major >= 14, "Required macOS major must be at least 14.")


def host_record(major):
    version = platform.mac_ver()[0]
    machine = platform.machine().lower()
    system = platform.system()
    return {"system": system, "macOSVersion": version or "unknown", "macOSBuild": "unknown",
            "cpu": machine, "requiredMacOSMajor": major,
            "qualifiesRequiredHost": system == "Darwin" and machine == "arm64"
            and re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", version) is not None
            and version.split(".")[0] == str(major)}


def project_hashes(path):
    return {name: digest for name, digest in shared.fixture_hashes(path).items()
            if name.split("/", 1)[0] not in {".git", ".pkglift"}}


def validate_auto(analysis, plan):
    candidates = [item for item in analysis.get("candidates", [])
                  if item.get("pod", {}).get("isDirect") is True and item.get("classification") == "AUTO"]
    entries = [item for item in plan.get("entries", []) if item.get("classification") == "AUTO"]
    require(len(candidates) == len(entries) == 1
            and candidates[0].get("pod", {}).get("name") == entries[0].get("podName") == "SDWebImage",
            "Reviewed direct AUTO set must contain only SDWebImage.")
    entry = entries[0]
    require(entry.get("targetName") == "PkgLiftMixedFixture"
            and entry.get("packageCandidate", {}).get("products") == ["SDWebImage"]
            and entry.get("targetSourceProfile", {}).get("completeness") == "complete"
            and set(entry.get("targetSourceProfile", {}).get("languages", [])) == {"swift", "objectiveC"},
            "Reviewed mixed-language target or package product evidence changed.")


def verify(args, output):
    validate_identity(args)
    summary = {"schemaVersion": 1, "recordedAt": datetime.now(timezone.utc).isoformat(),
               "status": "failed", "metadataOnly": False, "acceptanceScope": "signed-core-runtime-structural-apply",
               "consumerBuildTested": False, "sourceCommit": args.source_commit, "version": args.version,
               "expectedArchiveSHA256": args.archive_sha256, "expectedBinarySHA256": args.binary_sha256,
               "host": host_record(args.required_macos_major), "runner": shared.runner_record(),
               "commands": {}}
    args._summary = summary
    require(summary["host"]["qualifiesRequiredHost"], "Host does not match required macOS major and Apple Silicon.")
    require(args.archive.is_file() and not args.archive.is_symlink(), "Archive must be a regular file.")
    summary["archiveSHA256"] = shared.sha256_file(args.archive)
    require(summary["archiveSHA256"] == args.archive_sha256, "Archive SHA-256 does not match signed candidate.")
    original = shared.fixture_hashes(args.fixture)
    require(not any(name.split("/", 1)[0] in {".git", ".pkglift"} for name in original),
            "Repository fixture must not contain Git or prior migration state.")

    def run(name, command, cwd=output):
        result, stdout = shared.command_result([str(value) for value in command], cwd)
        summary["commands"][name] = result
        require(result["status"] == "passed", "Required runtime command failed: " + name)
        return stdout

    def document(name, command, cwd):
        try:
            value = json.loads(run(name, command, cwd))
        except json.JSONDecodeError as error:
            raise VerificationError("Runtime command did not return JSON: " + name) from error
        require(isinstance(value, dict), "Runtime command did not return an object: " + name)
        return value

    build = run("macOSBuildVersion", ["/usr/bin/sw_vers", "-buildVersion"]).strip()
    require(shared.BUILD_VERSION_RE.fullmatch(build) is not None, "macOS build version is invalid.")
    summary["host"]["macOSBuild"] = build
    runtime = output / "quarantined-cli"
    runtime.mkdir()
    shared.safe_extract(args.archive, runtime)
    binary = runtime / "pkglift"
    require(binary.is_file() and os.access(binary, os.X_OK), "Extracted CLI is not executable.")
    summary["binarySHA256"] = shared.sha256_file(binary)
    require(summary["binarySHA256"] == args.binary_sha256, "Binary SHA-256 does not match signed candidate.")
    quarantine = "0083;0;PkgLiftCandidateRuntime;"
    run("setQuarantine", ["/usr/bin/xattr", "-w", "com.apple.quarantine", quarantine, binary])
    require(run("readQuarantine", ["/usr/bin/xattr", "-p", "com.apple.quarantine", binary]).strip() == quarantine,
            "Could not prove quarantine on the extracted candidate.")
    run("codesignVerify", ["/usr/bin/codesign", "--verify", "--strict", "--verbose=4", binary])
    require(run("version", [binary, "version"]).strip() == args.version, "Candidate version mismatch.")
    run("registryValidate", [binary, "registry", "validate"])

    changed = verify_fixture(args.fixture, binary, output, original, run, document)
    require(shared.sha256_file(binary) == args.binary_sha256, "Candidate bytes changed during acceptance.")
    summary.update(status="passed", quarantinePresent=True, signaturePassed=True,
                   repositoryFixtureUnchanged=True, dryRunUnchanged=True, changedProjectFiles=changed)
    return summary


def verify_fixture(source_fixture, binary, output, original, run, document):
    """Exercise core commands; signature and host checks are performed by verify."""
    fixture = output / "fixture"
    shutil.copytree(source_fixture, fixture)
    require(shared.fixture_hashes(fixture) == original, "Copied fixture differs from repository fixture.")
    run("gitInit", ["/usr/bin/git", "-c", "init.templateDir=", "init", "--quiet", fixture])
    (fixture / ".git/info").mkdir(exist_ok=True)
    (fixture / ".git/info/exclude").write_text("/.pkglift/\n", encoding="utf-8")
    run("gitAdd", ["/usr/bin/git", "add", "--all"], fixture)
    run("gitBaseline", ["/usr/bin/git", "-c", "user.name=PkgLift runtime fixture", "-c",
                        "user.email=runtime@invalid.example", "-c", "commit.gpgsign=false", "-c",
                        "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "Disposable runtime baseline"], fixture)
    common = ["--path", fixture, "--project", "PkgLiftMixedFixture.xcodeproj", "--no-color"]
    before_analysis = shared.fixture_hashes(fixture)
    analysis = document("analyze", [binary, "analyze", *common, "--portable-json"], fixture)
    require(shared.fixture_hashes(fixture) == before_analysis, "Analysis changed fixture bytes.")
    run("plan", [binary, "plan", *common, "--portable-json"], fixture)
    require(project_hashes(fixture) == original, "Planning changed consumer project bytes.")
    try:
        plan = json.loads((fixture / ".pkglift/plan.json").read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise VerificationError("Saved plan is missing or invalid.") from error
    validate_auto(analysis, plan)
    require(run("gitClean", ["/usr/bin/git", "status", "--porcelain"], fixture).strip() == "",
            "Fixture must be clean before apply.")
    dry_before = shared.fixture_hashes(fixture)
    run("dryRun", [binary, "migrate", *common], fixture)
    require(shared.fixture_hashes(fixture) == dry_before, "Dry run changed fixture bytes.")
    run("apply", [binary, "migrate", *common, "--apply"], fixture)
    after = project_hashes(fixture)
    changed = sorted(name for name in set(original) | set(after) if original.get(name) != after.get(name))
    require(changed == ["PkgLiftMixedFixture.xcodeproj/project.pbxproj", "Podfile"],
            "Apply did not change exactly the reviewed project and Podfile.")
    expected_podfile = (source_fixture / "Podfile").read_bytes().replace(
        b"  pod 'SDWebImage', '5.18.1', :modular_headers => true\n", b"")
    require((fixture / "Podfile").read_bytes() == expected_podfile, "Apply changed unrelated Podfile content.")
    verification = document("structuralVerify", [binary, "verify", *common, "--json"], fixture)
    (output / "structural-verification.json").write_text(json.dumps(verification, indent=2) + "\n")
    require(shared.fixture_hashes(source_fixture) == original, "Repository-owned fixture changed.")
    return changed


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    for option in ("archive", "fixture", "output-dir"):
        result.add_argument("--" + option, type=Path, required=True)
    for option in ("archive-sha256", "binary-sha256", "source-commit", "version"):
        result.add_argument("--" + option, required=True)
    result.add_argument("--required-macos-major", type=int, required=True)
    return result


def main():
    args = parser().parse_args()
    output = args.output_dir.absolute()
    summary = {"schemaVersion": 1, "status": "failed"}
    created = False
    try:
        validate_identity(args)
        require(not output.exists() and not output.is_symlink(), "Output directory must be new.")
        require(not output.resolve().is_relative_to(args.fixture.resolve()), "Output must be outside repository fixture.")
        output.mkdir(parents=True)
        created = True
        summary = verify(args, output)
    except (VerificationError, OSError, ValueError, shared.tarfile.TarError) as error:
        summary = getattr(args, "_summary", summary)
        summary.update(status="failed", failure=str(error))
    serialized = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    if created:
        (output / "summary.json").write_text(serialized, encoding="utf-8")
    sys.stdout.write(serialized)
    return 0 if summary["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
