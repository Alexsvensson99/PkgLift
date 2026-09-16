#!/usr/bin/env python3
"""Run a bounded, privacy-safe runtime qualification of a published PkgLift CLI."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import re
import subprocess
import sys
import tarfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any, NoReturn


EXPECTED_ARCHIVE_SHA256 = "ad0747b3c10794ca93f23dc51953b3d234ddcfdabf4af1b5d4de5cd14876bd12"
EXPECTED_BINARY_SHA256 = "9b3160a9853324a49a67f3022e8492326cf90b56fba4dfa01f31e2623d26fd00"
EXPECTED_RELEASE_COMMIT = "7d976d70e66a584e2e25db9852ac0e53bb6201b9"
EXPECTED_VERSION = "0.10.0"
BUNDLE_NAME = "PkgLift_PkgLiftRegistry.bundle"
MAX_ARCHIVE_MEMBERS = 5_000
MAX_ARCHIVE_BYTES = 128 * 1024 * 1024
COMMAND_TIMEOUT_SECONDS = 45
BUILD_VERSION_RE = re.compile(r"^[A-Za-z0-9.]{1,80}$")
IMAGE_VERSION_RE = re.compile(r"^[A-Za-z0-9._-]{1,80}$")


class VerificationError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def host_record() -> dict[str, Any]:
    version = platform.mac_ver()[0]
    machine = platform.machine().lower()
    system = platform.system()
    qualifies = system == "Darwin" and version.split(".", 1)[0] == "14" and machine == "arm64"
    return {
        "system": system,
        "macOSBuild": "unknown",
        "macOSVersion": version or "unknown",
        "cpu": machine or "unknown",
        "qualifiesMinimumHost": qualifies,
    }


def runner_record() -> dict[str, Any]:
    image_os = os.environ.get("ImageOS", "")
    image_version = os.environ.get("ImageVersion", "")
    return {
        "imageOS": image_os if image_os in {"macos14", "macos-14", "macos-14-arm64"} else "unknown",
        "imageVersion": image_version if IMAGE_VERSION_RE.fullmatch(image_version) else "unknown",
    }


def validate_archive(archive: tarfile.TarFile) -> list[tarfile.TarInfo]:
    members = archive.getmembers()
    if not members or len(members) > MAX_ARCHIVE_MEMBERS:
        raise VerificationError("Archive member count is outside the allowed bound.")
    total_bytes = 0
    names: set[str] = set()
    top_levels: set[str] = set()
    binary_count = 0
    bundle_files = 0
    for member in members:
        name = member.name.rstrip("/")
        candidate = PurePosixPath(name)
        if not name or candidate.is_absolute() or ".." in candidate.parts or candidate.as_posix() != name:
            raise VerificationError("Archive contains an unsafe member path.")
        if name in names:
            raise VerificationError("Archive contains a duplicate member path.")
        names.add(name)
        if member.issym() or member.islnk() or not (member.isfile() or member.isdir()):
            raise VerificationError("Archive contains an unsupported member type.")
        if member.isfile():
            total_bytes += member.size
            if total_bytes > MAX_ARCHIVE_BYTES:
                raise VerificationError("Archive exceeds the uncompressed size limit.")
        top_levels.add(candidate.parts[0])
        if name == "pkglift" and member.isfile():
            binary_count += 1
        if name.startswith(BUNDLE_NAME + "/") and member.isfile():
            bundle_files += 1
    if top_levels != {"pkglift", BUNDLE_NAME} or binary_count != 1 or bundle_files < 1:
        raise VerificationError("Archive does not contain the expected CLI and registry bundle.")
    return members


def safe_extract(archive_path: Path, destination: Path) -> None:
    with tarfile.open(archive_path, "r:gz") as archive:
        members = validate_archive(archive)
        archive.extractall(destination, members=members)
    if any(path.is_symlink() for path in destination.rglob("*")):
        raise VerificationError("Extracted archive contains a symbolic link.")


def command_result(command: list[str], cwd: Path) -> tuple[dict[str, Any], str]:
    try:
        result = subprocess.run(
            command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=COMMAND_TIMEOUT_SECONDS, check=False,
        )
    except subprocess.TimeoutExpired:
        return {"status": "timedOut", "exitCode": None}, ""
    except OSError:
        return {"status": "failed", "exitCode": None}, ""
    return {
        "status": "passed" if result.returncode == 0 else "failed",
        "exitCode": result.returncode,
    }, result.stdout


def fixture_hashes(fixture: Path) -> dict[str, str]:
    if not fixture.is_dir() or fixture.is_symlink():
        raise VerificationError("Fixture must be a real directory.")
    hashes: dict[str, str] = {}
    for path in sorted(fixture.rglob("*")):
        if path.is_symlink():
            raise VerificationError("Fixture must not contain symbolic links.")
        if path.is_file():
            hashes[path.relative_to(fixture).as_posix()] = sha256_file(path)
    if not hashes:
        raise VerificationError("Fixture must contain files.")
    return hashes


def fail(message: str) -> NoReturn:
    raise VerificationError(message)


def verify(args: argparse.Namespace, output: Path) -> dict[str, Any]:
    recorded_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    host = host_record()
    summary: dict[str, Any] = {
        "schemaVersion": 1,
        "metadataOnly": False,
        "releaseAcceptance": False,
        "recordedAt": recorded_at,
        "host": host,
        "runner": runner_record(),
        "releaseCommit": EXPECTED_RELEASE_COMMIT,
        "archiveSHA256": None,
        "binarySHA256": None,
        "quarantinePresent": False,
        "signaturePassed": False,
        "commands": {},
        "fixtureUnchanged": False,
        "status": "failed",
    }
    args._summary = summary
    build, build_stdout = command_result(["/usr/bin/sw_vers", "-buildVersion"], output)
    summary["commands"]["macOSBuildVersion"] = build
    if build["status"] == "passed" and BUILD_VERSION_RE.fullmatch(build_stdout.strip()):
        host["macOSBuild"] = build_stdout.strip()
    else:
        fail("Could not record the exact macOS build version.")
    if not host["qualifiesMinimumHost"] and not args.allow_other_host:
        summary["failure"] = "Host does not meet the macOS 14 arm64 qualification requirement."
        return summary

    archive = args.archive
    if not archive.is_file() or archive.is_symlink():
        fail("Archive must be a regular file.")
    summary["archiveSHA256"] = sha256_file(archive)
    if summary["archiveSHA256"] != EXPECTED_ARCHIVE_SHA256:
        fail("Archive SHA-256 does not match the published v0.10.0 artifact.")

    runtime = output / "runtime"
    runtime.mkdir()
    safe_extract(archive, runtime)
    binary = runtime / "pkglift"
    bundle = runtime / BUNDLE_NAME
    if not binary.is_file() or binary.is_symlink() or not os.access(binary, os.X_OK) or not bundle.is_dir():
        fail("Extracted CLI or registry bundle is missing.")
    summary["binarySHA256"] = sha256_file(binary)
    if summary["binarySHA256"] != EXPECTED_BINARY_SHA256:
        fail("Extracted CLI SHA-256 does not match the published v0.10.0 artifact.")

    candidate = output / "quarantined-cli"
    candidate.mkdir()
    candidate_binary = candidate / "pkglift"
    shutil.copy2(binary, candidate_binary)
    shutil.copytree(bundle, candidate / BUNDLE_NAME)
    quarantine_value = "0083;0;PkgLiftRuntimeQualification;"
    quarantine, _ = command_result(["/usr/bin/xattr", "-w", "com.apple.quarantine", quarantine_value, str(candidate_binary)], output)
    summary["commands"]["setQuarantine"] = quarantine
    present, value = command_result(["/usr/bin/xattr", "-p", "com.apple.quarantine", str(candidate_binary)], output)
    summary["commands"]["readQuarantine"] = present
    summary["quarantinePresent"] = present["status"] == "passed" and value.strip() == quarantine_value
    if not summary["quarantinePresent"]:
        fail("Could not prove quarantine on the fresh executable copy.")

    signature, _ = command_result(["/usr/bin/codesign", "--verify", "--strict", "--verbose=4", str(candidate_binary)], output)
    summary["commands"]["codesignVerify"] = signature
    summary["signaturePassed"] = signature["status"] == "passed"
    if not summary["signaturePassed"]:
        fail("Strict code-signature verification failed.")

    version, version_stdout = command_result([str(candidate_binary), "version"], output)
    summary["commands"]["version"] = version
    if version["status"] != "passed" or version_stdout.strip() != EXPECTED_VERSION:
        fail("Published CLI did not report the expected version.")
    registry, _ = command_result([str(candidate_binary), "registry", "validate"], output)
    summary["commands"]["registryValidate"] = registry
    if registry["status"] != "passed":
        fail("Bundled registry validation failed.")

    original_fixture = fixture_hashes(args.fixture)
    copied_fixture = output / "fixture"
    shutil.copytree(args.fixture, copied_fixture, symlinks=False)
    if original_fixture != fixture_hashes(copied_fixture):
        fail("Fixture copy does not match the repository-owned fixture.")
    analyze, analyze_stdout = command_result(
        [str(candidate_binary), "analyze", "--path", str(copied_fixture), "--portable-json"], output
    )
    summary["commands"]["analyzePortableJSON"] = analyze
    if analyze["status"] != "passed":
        fail("Portable fixture analysis failed.")
    try:
        json.loads(analyze_stdout)
    except json.JSONDecodeError:
        fail("Portable fixture analysis did not produce JSON.")
    summary["fixtureUnchanged"] = (
        original_fixture == fixture_hashes(args.fixture)
        and original_fixture == fixture_hashes(copied_fixture)
    )
    if not summary["fixtureUnchanged"]:
        fail("Fixture bytes changed during analysis.")
    summary["status"] = "passed"
    return summary


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--archive", type=Path, required=True)
    result.add_argument("--output-dir", type=Path, required=True)
    result.add_argument("--fixture", type=Path, required=True)
    result.add_argument("--allow-other-host", action="store_true")
    return result


def main() -> int:
    args = parser().parse_args()
    output = args.output_dir.resolve()
    if output.exists():
        summary = {
            "schemaVersion": 1, "metadataOnly": False, "releaseAcceptance": False,
            "recordedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "host": host_record(), "runner": runner_record(), "status": "failed",
            "failure": "Output directory must be new.",
        }
        sys.stdout.write(json.dumps(summary, indent=2, sort_keys=True) + "\n")
        return 1
    args.archive = args.archive.resolve()
    args.fixture = args.fixture.resolve()
    args.output_dir = output
    output.mkdir(parents=True)
    try:
        summary = verify(args, output)
    except VerificationError as error:
        summary = getattr(args, "_summary", None)
        if summary is None:
            summary = {
                "schemaVersion": 1, "metadataOnly": False, "releaseAcceptance": False,
                "recordedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                "host": host_record(), "runner": runner_record(), "status": "failed",
            }
        summary["status"] = "failed"
        summary["failure"] = str(error)
    serialized = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    (output / "summary.json").write_text(serialized, encoding="utf-8")
    sys.stdout.write(serialized)
    return 0 if summary["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
