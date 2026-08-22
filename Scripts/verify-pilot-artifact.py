#!/usr/bin/env python3
"""Fail-closed verification for a same-run PkgLift pilot artifact."""

from __future__ import annotations

import hashlib
import os
import platform
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath
from typing import NoReturn


ARCHIVE_NAME = "pkglift-pilot-binary.tar.gz"
BUNDLE_NAME = "PkgLift_PkgLiftRegistry.bundle"
MANIFEST_KEYS = {
    "binary_sha256",
    "bundle_sha256",
    "producer_job",
    "producer_run_attempt",
    "repository",
    "run_id",
    "runner_arch",
    "schema",
    "source_sha",
}
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")
SOURCE_SHA_PATTERN = re.compile(r"[0-9a-f]{40}")


def fail(message: str) -> NoReturn:
    raise SystemExit(message)


def required_environment(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        fail(f"Missing required environment variable: {name}")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def parse_manifest(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line_number, line in enumerate(path.read_text(encoding="UTF-8").splitlines(), 1):
        if "=" not in line:
            fail(f"Malformed manifest line {line_number}.")
        key, value = line.split("=", 1)
        if not key or not value:
            fail(f"Empty manifest key or value on line {line_number}.")
        if key in values:
            fail(f"Duplicate manifest key: {key}")
        values[key] = value

    if set(values) != MANIFEST_KEYS:
        missing = sorted(MANIFEST_KEYS.difference(values))
        unexpected = sorted(set(values).difference(MANIFEST_KEYS))
        fail(f"Manifest keys differ; missing={missing}, unexpected={unexpected}")
    return values


def validate_archive_members(archive: tarfile.TarFile) -> list[tarfile.TarInfo]:
    members = archive.getmembers()
    if not members:
        fail("Pilot artifact archive is empty.")

    names: set[str] = set()
    top_levels: set[str] = set()
    bundle_files = 0
    binary_files = 0
    manifest_files = 0

    for member in members:
        name = member.name.rstrip("/")
        candidate = PurePosixPath(name)
        if not name or candidate.is_absolute() or ".." in candidate.parts:
            fail(f"Unsafe archive member path: {member.name}")
        if candidate.as_posix() != name:
            fail(f"Non-canonical archive member path: {member.name}")
        if name in names:
            fail(f"Duplicate archive member: {name}")
        names.add(name)

        top_level = candidate.parts[0]
        if top_level not in {"pkglift", BUNDLE_NAME, "manifest.txt"}:
            fail(f"Unexpected archive top-level entry: {top_level}")
        top_levels.add(top_level)

        if member.issym() or member.islnk() or not (member.isfile() or member.isdir()):
            fail(f"Unsupported archive member type: {member.name}")
        if name == "pkglift" and member.isfile():
            binary_files += 1
        if name == "manifest.txt" and member.isfile():
            manifest_files += 1
        if name.startswith(f"{BUNDLE_NAME}/") and member.isfile():
            bundle_files += 1

    expected_top_levels = {"pkglift", BUNDLE_NAME, "manifest.txt"}
    if top_levels != expected_top_levels:
        fail(f"Archive top-level entries differ: {sorted(top_levels)}")
    if binary_files != 1 or manifest_files != 1 or bundle_files < 1:
        fail(
            "Archive must contain one executable, one manifest, and a non-empty registry bundle."
        )
    return members


def main() -> None:
    if len(sys.argv) != 3:
        fail(f"Usage: {sys.argv[0]} <archive> <new-runtime-directory>")

    archive_input = Path(sys.argv[1])
    if archive_input.is_symlink():
        fail(f"Pilot archive must not be a symbolic link: {archive_input}")
    archive_path = archive_input.resolve()
    runtime_directory = Path(sys.argv[2]).resolve()
    checksum_path = archive_path.with_name(f"{archive_path.name}.sha256")

    expected = {
        "archive_sha256": required_environment("PKGLIFT_EXPECTED_ARCHIVE_SHA256"),
        "binary_sha256": required_environment("PKGLIFT_EXPECTED_BINARY_SHA256"),
        "producer_run_attempt": required_environment("PKGLIFT_EXPECTED_PRODUCER_ATTEMPT"),
        "repository": required_environment("PKGLIFT_EXPECTED_REPOSITORY"),
        "run_id": required_environment("PKGLIFT_EXPECTED_RUN_ID"),
        "source_sha": required_environment("PKGLIFT_EXPECTED_SOURCE_SHA"),
    }
    if not SHA256_PATTERN.fullmatch(expected["archive_sha256"]):
        fail("Expected archive SHA-256 is malformed.")
    if not SHA256_PATTERN.fullmatch(expected["binary_sha256"]):
        fail("Expected binary SHA-256 is malformed.")
    if not SOURCE_SHA_PATTERN.fullmatch(expected["source_sha"]):
        fail("Expected source SHA is malformed.")
    if not expected["run_id"].isdigit() or not expected["producer_run_attempt"].isdigit():
        fail("Expected run identifiers must be positive integers.")

    if archive_path.name != ARCHIVE_NAME or not archive_path.is_file() or archive_path.is_symlink():
        fail(f"Missing regular pilot archive: {archive_path}")
    if not checksum_path.is_file() or checksum_path.is_symlink():
        fail(f"Missing regular pilot checksum: {checksum_path}")
    downloaded_entries = sorted(path.name for path in archive_path.parent.iterdir())
    if downloaded_entries != [ARCHIVE_NAME, f"{ARCHIVE_NAME}.sha256"]:
        fail(f"Downloaded artifact has unexpected entries: {downloaded_entries}")

    expected_checksum_line = f"{expected['archive_sha256']}  {ARCHIVE_NAME}\n"
    if checksum_path.read_text(encoding="ASCII") != expected_checksum_line:
        fail("Pilot artifact checksum file does not match the producer output.")
    actual_archive_sha256 = sha256_file(archive_path)
    if actual_archive_sha256 != expected["archive_sha256"]:
        fail("Pilot artifact archive checksum mismatch.")

    if runtime_directory.exists():
        fail(f"Runtime directory must not already exist: {runtime_directory}")
    runtime_directory.parent.mkdir(parents=True, exist_ok=True)
    runtime_directory.mkdir()

    with tarfile.open(archive_path, "r:gz") as archive:
        members = validate_archive_members(archive)
        archive.extractall(runtime_directory, members=members)

    if any(path.is_symlink() for path in runtime_directory.rglob("*")):
        fail("Extracted pilot artifact must not contain symbolic links.")

    binary_path = runtime_directory / "pkglift"
    bundle_path = runtime_directory / BUNDLE_NAME
    manifest_path = runtime_directory / "manifest.txt"
    if not binary_path.is_file() or binary_path.is_symlink() or not os.access(binary_path, os.X_OK):
        fail("Extracted PkgLift binary is missing or not executable.")
    if not bundle_path.is_dir() or bundle_path.is_symlink():
        fail("Extracted registry bundle is missing.")

    manifest = parse_manifest(manifest_path)
    manifest_expected = {
        "binary_sha256": expected["binary_sha256"],
        "producer_job": "build_pilot_toolchain",
        "producer_run_attempt": expected["producer_run_attempt"],
        "repository": expected["repository"],
        "run_id": expected["run_id"],
        "schema": "1",
        "source_sha": expected["source_sha"],
    }
    for key, value in manifest_expected.items():
        if manifest[key] != value:
            fail(f"Pilot artifact manifest mismatch for {key}.")

    actual_binary_sha256 = sha256_file(binary_path)
    if actual_binary_sha256 != manifest["binary_sha256"]:
        fail("Extracted PkgLift binary checksum mismatch.")

    hash_script = Path(__file__).resolve().with_name("hash-pilot-tree.py")
    bundle_hash_result = subprocess.run(
        [sys.executable, str(hash_script), str(bundle_path)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    if bundle_hash_result.stdout.strip() != manifest["bundle_sha256"]:
        fail("Extracted registry bundle checksum mismatch.")
    if manifest["runner_arch"] != platform.machine():
        fail(
            f"Pilot artifact architecture {manifest['runner_arch']} does not match "
            f"consumer {platform.machine()}."
        )

    version_result = subprocess.run(
        [str(binary_path), "version"],
        check=True,
        cwd=tempfile.gettempdir(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    subprocess.run(
        [str(binary_path), "registry", "validate"],
        check=True,
        cwd=tempfile.gettempdir(),
    )

    github_environment = os.environ.get("GITHUB_ENV", "")
    if github_environment:
        environment_values = {
            "PKGLIFT_ARTIFACT_RUN_ATTEMPT": manifest["producer_run_attempt"],
            "PKGLIFT_ARTIFACT_RUN_ID": manifest["run_id"],
            "PKGLIFT_ARTIFACT_SOURCE_SHA": manifest["source_sha"],
            "PKGLIFT_BINARY_SHA256": actual_binary_sha256,
            "PKGLIFT_BIN": str(binary_path),
        }
        with Path(github_environment).open("a", encoding="UTF-8") as output:
            for key, value in environment_values.items():
                if "\n" in value or "\r" in value:
                    fail(f"Refusing to export multiline environment value: {key}")
                output.write(f"{key}={value}\n")

    print(
        f"Verified PkgLift {version_result.stdout.strip()} from "
        f"{manifest['source_sha']} (binary SHA-256 {actual_binary_sha256})."
    )


if __name__ == "__main__":
    main()
