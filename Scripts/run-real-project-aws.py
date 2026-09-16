#!/usr/bin/env python3
"""Qualification runner for the pinned AWS Grid Feed partial migration.

This program is intentionally specific.  It is executed only by the separately
opted-in GitHub hosted qualification job; it is not a general project runner.
Only ``report/`` is suitable for artifact upload.  Source trees, dependency
specifications, locks and command output stay below ``private/``.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import plistlib
import re
import stat
import subprocess
import sys
import tarfile
import time
import urllib.request
from pathlib import Path
from typing import Any, Iterable, Mapping

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent

REPOSITORY = "https://github.com/aws-samples/amazon-ivs-grid-feed-for-ios-demo.git"
SOURCE_COMMIT = "5573a57d4cb7e10f7ad86f95c548ddfbeabc6e1d"
SOURCE_LICENSE = "MIT-0"
TARGET = "Grid Feed"
PROJECT = "Grid Feed.xcodeproj"
WORKSPACE = "Grid Feed.xcworkspace"
POD_VERSIONS = {"AmazonIVSPlayer": "1.40.0", "SDWebImage": "5.18.1"}
PACKAGE_URL = "https://github.com/SDWebImage/SDWebImage"
PACKAGE_GIT_URL = PACKAGE_URL + ".git"
PACKAGE_REVISION = "6e844d19679c9e0833ccc363d7f5a7c5f0c5f5d7"
PACKAGE_MANIFEST_URL = f"https://raw.githubusercontent.com/SDWebImage/SDWebImage/{PACKAGE_REVISION}/Package.swift"
PACKAGE_MANIFEST_SHA256 = "351f64c27724e6c1093403281257aed7118bf3456cf2f0b39bef64b9cfd8ae6e"
PRIVACY_RESOURCE_SHA256 = "03b2c70833a331a2b1efd11ff168ed02a8eadfd5e7d1fbf30eecc7509a4aea47"
PRIVACY_SYMLINK_SHA256 = "bc1f3592548b2319ca87acff5bfdbbcf5684b42d92a194f8e051d4bbe97aeabd"
PRIVACY_RESOURCE_SYMLINKS = (
    "SDWebImage/Resources/PrivacyInfo.xcprivacy",
    "SDWebImageMapKit/Resources/PrivacyInfo.xcprivacy",
)
COCOAPODS_VERSION = "1.17.0"
AMAZON_ARCHIVE_URL = "https://player.live-video.net/1.40.0/AmazonIVSPlayer.tgz"
AMAZON_ARCHIVE_SHA256 = "e7cacfbcaead184d0efca1c53d656d64ee2a46721b9097198848156a5476c5d6"
AMAZON_LICENSE_URL = "https://player.live-video.net/LICENSE.txt"
AMAZON_LICENSE_SHA256 = "177afaa4a305169ccd9e6200243ccde30e0ca649fbe1b3cf2046171440c35636"

PODSPEC_INPUTS = {
    "AmazonIVSPlayer": {
        "url": "https://raw.githubusercontent.com/CocoaPods/Specs/95fb77b21fd1363f579fbaf5684fab0ea796c31d/Specs/4/3/2/AmazonIVSPlayer/1.40.0/AmazonIVSPlayer.podspec.json",
        "rawSHA256": "3fdb29a9f3b1440b5cfbd51e34af247be44dd376aeaf6424074ab6d07e099770",
        "rawSHA1": "b1dbf89d0067d016ab734dc6e7ae799ea52101cd",
        "canonicalSHA256": "6d633b11d9d36794d1cd9388bda1e142f0cd528d75617d305bc3282f11ed52d9",
    },
    "SDWebImage": {
        "url": "https://raw.githubusercontent.com/CocoaPods/Specs/836af618f46996d9e8883146851b811a63c76d8e/Specs/1/1/7/SDWebImage/5.18.1/SDWebImage.podspec.json",
        "rawSHA256": "21f5f15b959199ab1eab0c01ab484a1a16e7760b6e4e292622fa32fc5702861c",
        "rawSHA1": "ebdbcebc7933a45226d9313bd0118bc052ad458b",
        "canonicalSHA256": "c3b6e8f1777a8043a4d4ef1381889d2968b7d35e1ef24d8966b0bae1357f4452",
    },
}

EXPECTED_SOURCE_HASHES = {
    "Podfile": "35067ca46eea7cbb342159876eef4f161a1c4cfd3f049e116a14750db10e406c",
    "Podfile.lock": "1f7616891fb05db30a51ce628146f73b4b94ee177c20c358f2e6416e262aec8c",
    "Grid Feed.xcworkspace/contents.xcworkspacedata": "59cd30dad60c7cc8c5a30bf3f4c72bcb78ebfeb346ce9999b1d34b62139d04ec",
    "Grid Feed.xcodeproj/project.pbxproj": "64335e159b0d5aa2d6fe1bce3cd52ef3ef55bf6c9b6436eda3e7a98fedcde23c",
    "LICENSE": "7cb750713252efd1d578837ba8785b61319109906f0c10b87adab7cf4badfc42",
}

OUTCOMES = {
    "passed-migration",
    "inconclusive-baseline",
    "blocked-input",
    "failed-safety",
    "failed-migration",
}
POD_INSTALL_DIAGNOSTIC_LABELS = {
    "baseline-pod-install",
    "migration-pod-install",
    "post-migration-pod-install",
}


class QualificationError(RuntimeError):
    def __init__(self, outcome: str, message: str):
        if outcome not in OUTCOMES:
            raise ValueError(f"invalid outcome: {outcome}")
        super().__init__(message)
        self.outcome = outcome


def require(condition: bool, message: str, outcome: str = "failed-safety") -> None:
    if not condition:
        raise QualificationError(outcome, message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_sha256(value: Any) -> str:
    return sha256_bytes(json.dumps(value, sort_keys=True, separators=(",", ":")).encode())


def file_sha256(path: Path) -> str:
    with path.open("rb") as handle:
        digest = hashlib.sha256()
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _under(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False


def validate_runtime_contract(binary: Path, output: Path, env: Mapping[str, str]) -> dict[str, Any]:
    """Validate all non-network inputs before creating output or running a command."""
    require(env.get("GITHUB_ACTIONS") == "true", "runner requires GITHUB_ACTIONS=true", "blocked-input")
    require(env.get("RUNNER_ENVIRONMENT") == "github-hosted", "runner requires a GitHub-hosted runner", "blocked-input")
    runner_temp_text = env.get("RUNNER_TEMP", "")
    require(bool(runner_temp_text), "RUNNER_TEMP is required", "blocked-input")
    runner_temp = Path(runner_temp_text).expanduser().resolve(strict=True)
    require(output.is_absolute(), "--output must be absolute", "blocked-input")
    require(not output.is_symlink(), "--output must not be a symlink", "blocked-input")
    output = output.resolve(strict=False)
    require(output.parent == runner_temp, "--output must be a direct child of RUNNER_TEMP", "blocked-input")
    require(not output.exists(), "--output must not already exist", "blocked-input")
    require(not _under(runner_temp, ROOT) and not _under(ROOT, output),
            "qualification output overlaps the PkgLift checkout", "blocked-input")
    require(binary.is_absolute(), "--pkglift must be absolute", "blocked-input")
    require(not binary.is_symlink(), "--pkglift must not be a symlink", "blocked-input")
    binary = binary.resolve(strict=True)
    require(binary.is_file() and os.access(binary, os.X_OK), "--pkglift must be an executable file", "blocked-input")
    expected_hash = env.get("PKGLIFT_BINARY_SHA256", "")
    require(bool(re.fullmatch(r"[0-9a-f]{64}", expected_hash)), "missing or malformed PKGLIFT_BINARY_SHA256", "blocked-input")
    require(file_sha256(binary) == expected_hash, "PkgLift binary hash differs from verified artifact", "blocked-input")
    source_sha = env.get("PKGLIFT_ARTIFACT_SOURCE_SHA", "")
    github_sha = env.get("GITHUB_SHA", "")
    require(bool(re.fullmatch(r"[0-9a-f]{40}", source_sha)), "missing or malformed artifact source SHA", "blocked-input")
    require(source_sha == github_sha, "artifact source SHA does not match workflow SHA", "blocked-input")
    run_id = env.get("PKGLIFT_ARTIFACT_RUN_ID", "")
    attempt = env.get("PKGLIFT_ARTIFACT_RUN_ATTEMPT", "")
    require(run_id.isdigit() and int(run_id) > 0 and run_id == env.get("GITHUB_RUN_ID"),
            "artifact run ID is missing or differs from current workflow", "blocked-input")
    require(attempt.isdigit() and int(attempt) > 0, "missing or malformed artifact run attempt", "blocked-input")
    require(bool(re.fullmatch(r"[^/\s]+/[^/\s]+", env.get("GITHUB_REPOSITORY", ""))), "invalid GITHUB_REPOSITORY", "blocked-input")
    manifest_path = binary.parent / "manifest.txt"
    require(manifest_path.is_file() and not manifest_path.is_symlink(), "verified artifact manifest is missing", "blocked-input")
    try:
        manifest = dict(line.split("=", 1) for line in manifest_path.read_text().splitlines())
    except ValueError as error:
        raise QualificationError("blocked-input", "artifact manifest is malformed") from error
    require(manifest.get("binary_sha256") == expected_hash and manifest.get("source_sha") == source_sha
            and manifest.get("run_id") == run_id and manifest.get("producer_run_attempt") == attempt,
            "artifact manifest provenance differs from exported verification", "blocked-input")
    require(manifest.get("repository") == env.get("GITHUB_REPOSITORY"),
            "artifact manifest repository differs from current workflow", "blocked-input")
    require(bool(re.fullmatch(r"[0-9a-f]{64}", manifest.get("bundle_sha256", ""))),
            "artifact registry bundle hash is missing", "blocked-input")
    return {
        "binary": binary,
        "output": output,
        "runnerTemp": runner_temp,
        "artifact": {"sha256": expected_hash, "sourceSHA": source_sha, "runID": run_id,
                     "runAttempt": attempt, "registryBundleSHA256": manifest["bundle_sha256"],
                     "manifestSHA256": file_sha256(manifest_path)},
    }


def tree_snapshot(root: Path, exclude: Iterable[str] = (".git",)) -> dict[str, dict[str, Any]]:
    """Snapshot bytes, modes and symlink targets without following symlinks."""
    root = root.resolve(strict=True)
    excluded = set(exclude)
    result: dict[str, dict[str, Any]] = {}
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        dirs[:] = sorted(d for d in dirs if not (current_path == root and d in excluded))
        for name in sorted(dirs + files):
            path = current_path / name
            relative = path.relative_to(root).as_posix()
            if relative.split("/", 1)[0] in excluded:
                continue
            metadata = path.lstat()
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                result[relative] = {"kind": "symlink", "mode": mode, "target": os.readlink(path)}
            elif stat.S_ISDIR(metadata.st_mode):
                result[relative] = {"kind": "directory", "mode": mode}
            elif stat.S_ISREG(metadata.st_mode):
                result[relative] = {"kind": "file", "mode": mode, "sha256": file_sha256(path), "size": metadata.st_size}
            else:
                raise QualificationError("failed-safety", f"unsupported special file: {relative}")
    return result


def exclude_generated_plan(source: Path, relative: str) -> None:
    exclude_file = source / ".git/info/exclude"
    exclude_file.parent.mkdir(parents=True, exist_ok=True)
    with exclude_file.open("a") as handle:
        handle.write("\n/" + relative + "\n")


def tree_digest(snapshot: Mapping[str, Any]) -> str:
    return canonical_json_sha256(snapshot)


def changed_paths(before: Mapping[str, Any], after: Mapping[str, Any]) -> list[str]:
    return sorted(path for path in set(before) | set(after) if before.get(path) != after.get(path))


def _allowed_dependency_path(path: str) -> bool:
    allowed_exact = {"Podfile", "Podfile.lock", f"{PROJECT}/project.pbxproj", f"{WORKSPACE}/contents.xcworkspacedata"}
    allowed_exact.update({"Pods", ".pkglift", f"{PROJECT}/project.xcworkspace",
                          f"{PROJECT}/project.xcworkspace/xcshareddata", f"{WORKSPACE}/xcshareddata"})
    allowed_prefixes = ("Pods/", ".pkglift/", f"{PROJECT}/project.xcworkspace/xcshareddata/swiftpm/",
                        f"{WORKSPACE}/xcshareddata/swiftpm/")
    return path in allowed_exact or path.startswith(allowed_prefixes)


def validate_dependency_only_delta(before: Mapping[str, Any], after: Mapping[str, Any]) -> list[str]:
    changes = changed_paths(before, after)
    bad = [path for path in changes if not _allowed_dependency_path(path)]
    require(not bad, "non-dependency files changed: " + ", ".join(bad[:10]))
    return changes


def validate_dry_run(before: Mapping[str, Any], after: Mapping[str, Any]) -> None:
    require(before == after, "PkgLift dry run mutated the source tree")


def validate_dry_run_output(text: str) -> None:
    require(text.strip().splitlines() == [
        "Dry run mode. Add --apply to execute the migration plan.",
        "1 AUTO migration(s):",
        f"- SDWebImage -> {PACKAGE_URL}",
    ], "PkgLift dry-run actions differ from the reviewed plan")


def _walk_json(value: Any, path: str = "$") -> Iterable[tuple[str, str, Any]]:
    if isinstance(value, dict):
        for key, child in value.items():
            yield path, str(key), child
            yield from _walk_json(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _walk_json(child, f"{path}[{index}]")


def validate_podspec(document: Mapping[str, Any], name: str) -> dict[str, Any]:
    expected = POD_VERSIONS[name]
    require(document.get("name") == name and document.get("version") == expected,
            f"{name} podspec identity/version mismatch", "blocked-input")
    script_keys = {"prepare_command", "script_phase", "script_phases"}
    hooks = [f"{path}.{key}" for path, key, value in _walk_json(document) if key in script_keys and value not in (None, "", [], {})]
    require(not hooks, f"{name} podspec contains executable hook(s): {', '.join(hooks)}", "blocked-input")
    source = document.get("source")
    require(isinstance(source, dict), f"{name} podspec source is missing", "blocked-input")
    if name == "AmazonIVSPlayer":
        require(source.get("http") == "https://player.live-video.net/1.40.0/AmazonIVSPlayer.tgz",
                "AmazonIVSPlayer archive URL changed", "blocked-input")
        require(source.get("sha256") == "e7cacfbcaead184d0efca1c53d656d64ee2a46721b9097198848156a5476c5d6",
                "AmazonIVSPlayer archive digest changed", "blocked-input")
        vendored = document.get("vendored_frameworks")
        require(vendored == "AmazonIVSPlayer.xcframework" or vendored == ["AmazonIVSPlayer.xcframework"],
                "AmazonIVSPlayer vendored framework changed", "blocked-input")
    else:
        require(source.get("git") == PACKAGE_GIT_URL and source.get("tag") == expected,
                "SDWebImage source repo/tag changed", "blocked-input")
    dependency_names: set[str] = set()
    for _path, key, value in _walk_json(document):
        if key == "dependencies" and isinstance(value, dict):
            dependency_names.update(str(item) for item in value)
    if name == "AmazonIVSPlayer":
        require(not dependency_names, "AmazonIVSPlayer podspec dependency closure changed", "blocked-input")
    else:
        require(all(item == "SDWebImage" or item.startswith("SDWebImage/") for item in dependency_names),
                "SDWebImage podspec gained an external dependency", "blocked-input")
    return {"name": name, "version": expected, "canonicalSHA256": canonical_json_sha256(document), "hooks": []}


def validate_public_podspec_bytes(name: str, raw: bytes) -> tuple[dict[str, Any], dict[str, Any]]:
    source = PODSPEC_INPUTS[name]
    require(sha256_bytes(raw) == source["rawSHA256"], f"{name} public podspec byte hash changed", "blocked-input")
    require(hashlib.sha1(raw).hexdigest() == source["rawSHA1"], f"{name} public podspec lock checksum changed", "blocked-input")
    try:
        doc = json.loads(raw)
    except (ValueError, UnicodeDecodeError) as error:
        raise QualificationError("blocked-input", f"{name} podspec is invalid JSON") from error
    evidence = validate_podspec(doc, name)
    require(evidence["canonicalSHA256"] == source["canonicalSHA256"],
            f"{name} public podspec semantic hash changed", "blocked-input")
    return doc, evidence


def inspect_amazon_archive(path: Path) -> dict[str, Any]:
    require(file_sha256(path) == AMAZON_ARCHIVE_SHA256, "Amazon archive digest differs from podspec", "blocked-input")
    regular = directories = symlinks = executables = signatures = 0
    payload_tree: dict[str, dict[str, Any]] = {}
    total_size = 0
    try:
        with tarfile.open(path, "r:gz") as archive:
            members = archive.getmembers()
            normalized_members: dict[str, tarfile.TarInfo] = {}
            require(0 < len(members) <= 10000, "Amazon archive entry count is unsafe", "blocked-input")
            for member in members:
                name = member.name.removeprefix("./")
                pure = Path(name)
                require(name and not pure.is_absolute() and ".." not in pure.parts,
                        "Amazon archive contains an unsafe or unexpected path", "blocked-input")
                if name == "AmazonIVSPlayer":
                    require(member.isdir(), "Amazon archive wrapper is not a directory", "blocked-input")
                    directories += 1
                    continue
                if name.startswith("AmazonIVSPlayer/"):
                    name = name.removeprefix("AmazonIVSPlayer/")
                    pure = Path(name)
                require(pure.parts and pure.parts[0] == "AmazonIVSPlayer.xcframework",
                        "Amazon archive contains an unexpected top-level path", "blocked-input")
                normalized_members[name] = member
                require(not member.isdev() and not member.isfifo() and not member.islnk(),
                        "Amazon archive contains a device, FIFO, or hard link", "blocked-input")
                if member.isdir():
                    directories += 1
                elif member.issym():
                    symlinks += 1
                    target = Path(member.linkname)
                    require(not target.is_absolute() and ".." not in target.parts,
                            "Amazon archive contains an escaping symlink", "blocked-input")
                    payload_tree[name] = {"kind": "symlink", "target": member.linkname}
                elif member.isfile():
                    regular += 1
                    total_size += member.size
                    require(total_size <= 1024 * 1024 * 1024, "Amazon archive expands beyond the reviewed bound", "blocked-input")
                    lower = name.lower()
                    require(not lower.endswith((".sh", ".rb", ".py", ".pl", ".command")),
                            "Amazon archive contains an unreviewed script-shaped file", "blocked-input")
                    if "/_CodeSignature/" in name:
                        signatures += 1
                    extracted = archive.extractfile(member)
                    require(extracted is not None, "Amazon archive file is unreadable", "blocked-input")
                    payload_tree[name] = {"kind": "file", "sha256": sha256_bytes(extracted.read())}
                else:
                    raise QualificationError("blocked-input", "Amazon archive contains an unsupported entry type")
            plist_member = normalized_members.get("AmazonIVSPlayer.xcframework/Info.plist")
            require(plist_member is not None, "Amazon archive XCFramework Info.plist missing", "blocked-input")
            plist_file = archive.extractfile(plist_member)
            require(plist_file is not None, "Amazon XCFramework metadata is unreadable", "blocked-input")
            metadata = plistlib.loads(plist_file.read())
            libraries = metadata.get("AvailableLibraries", [])
            require(isinstance(libraries, list) and libraries, "Amazon XCFramework declares no slices", "blocked-input")
            slice_ids = []
            for library in libraries:
                identifier = library.get("LibraryIdentifier")
                library_path = library.get("LibraryPath")
                binary_path = library.get("BinaryPath")
                require(isinstance(identifier, str) and isinstance(library_path, str) and isinstance(binary_path, str)
                        and "/" not in identifier and ".." not in Path(library_path).parts,
                        "Amazon XCFramework slice metadata is unsafe", "blocked-input")
                prefix = f"AmazonIVSPlayer.xcframework/{identifier}/{library_path}"
                require(any(name == prefix or name.startswith(prefix + "/") for name in normalized_members),
                        "Amazon XCFramework slice path is missing", "blocked-input")
                binary_name = f"AmazonIVSPlayer.xcframework/{identifier}/{binary_path}"
                binary_member = normalized_members.get(binary_name)
                require(binary_member is not None and binary_member.isfile(),
                        "Amazon XCFramework declared binary is missing", "blocked-input")
                binary_file = archive.extractfile(binary_member)
                require(binary_file is not None
                        and binary_file.read(4) in {bytes.fromhex(value) for value in
                                                   ("feedface", "cefaedfe", "feedfacf", "cffaedfe",
                                                    "cafebabe", "bebafeca", "cafebabf", "bfbafeca")},
                        "Amazon XCFramework declared binary is not Mach-O", "blocked-input")
                executables += 1
                slice_ids.append(identifier)
    except (tarfile.TarError, OSError) as error:
        raise QualificationError("blocked-input", "Amazon archive is invalid") from error
    require(regular > 0 and executables > 0 and signatures > 0,
            "Amazon archive lacks expected framework executables or signatures", "blocked-input")
    return {"sha256": AMAZON_ARCHIVE_SHA256, "regularFiles": regular, "directories": directories,
            "symlinks": symlinks, "frameworkExecutables": executables, "signatureFiles": signatures,
            "expandedBytes": total_size, "sliceIdentifiers": sorted(slice_ids), "_payloadTree": payload_tree}


def validate_package_manifest_bytes(raw: bytes) -> dict[str, Any]:
    require(sha256_bytes(raw) == PACKAGE_MANIFEST_SHA256, "SDWebImage Package.swift hash changed", "blocked-input")
    text = raw.decode("utf-8")
    require("dependencies: []" in text and ".plugin(" not in text and ".binaryTarget(" not in text
            and "PackagePlugin" not in text, "SDWebImage manifest dependency/execution shape changed", "blocked-input")
    require('.copy("Resources/PrivacyInfo.xcprivacy")' in text,
            "SDWebImage privacy resource declaration changed", "blocked-input")
    return {"url": PACKAGE_MANIFEST_URL, "sha256": PACKAGE_MANIFEST_SHA256,
            "externalDependencies": 0, "plugins": 0, "binaryTargets": 0}


def selected_sdwebimage_sources(root: Path) -> dict[str, str]:
    paths = []
    for directory in (root / "SDWebImage/Core", root / "SDWebImage/Private"):
        require(directory.is_dir() and not directory.is_symlink(), "SDWebImage selected source directory is missing", "blocked-input")
        paths.extend(path for path in directory.rglob("*") if path.suffix in {".h", ".m"})
    paths.append(root / "WebImage/SDWebImage.h")
    require(len(paths) == 148 and len(set(paths)) == 148, "SDWebImage selected CocoaPods source count changed", "blocked-input")
    result = {}
    for path in paths:
        require(path.is_file() and not path.is_symlink(), "SDWebImage selected source is missing or symlinked", "blocked-input")
        result[path.relative_to(root).as_posix()] = file_sha256(path)
    return result


def validate_installed_dependency_payloads(root: Path, reference_sd: Path | None,
                                           amazon_payload_tree: Mapping[str, Any], include_sd: bool) -> dict[str, Any]:
    installed_amazon = root / "Pods/AmazonIVSPlayer/AmazonIVSPlayer.xcframework"
    require(installed_amazon.is_dir() and not installed_amazon.is_symlink(),
            "installed AmazonIVSPlayer XCFramework is missing", "blocked-input")
    actual_amazon = {}
    for path in installed_amazon.rglob("*"):
        relative = "AmazonIVSPlayer.xcframework/" + path.relative_to(installed_amazon).as_posix()
        if path.is_symlink():
            actual_amazon[relative] = {"kind": "symlink", "target": os.readlink(path)}
        elif path.is_file():
            actual_amazon[relative] = {"kind": "file", "sha256": file_sha256(path)}
    require(actual_amazon == amazon_payload_tree,
            "installed AmazonIVSPlayer payload differs from the digest-verified archive", "blocked-input")
    result = {"amazonPayloadTreeSHA256": canonical_json_sha256(actual_amazon)}
    installed_sd = root / "Pods/SDWebImage"
    if include_sd:
        require(reference_sd is not None, "reviewed SDWebImage source reference is unavailable", "blocked-input")
        expected_sources = selected_sdwebimage_sources(reference_sd)
        actual_sources = selected_sdwebimage_sources(installed_sd)
        require(actual_sources == expected_sources,
                "installed SDWebImage Core/Private sources differ from reviewed commit", "blocked-input")
        result.update(sdWebImageSelectedSourceCount=len(actual_sources),
                      sdWebImageSelectedTreeSHA256=canonical_json_sha256(actual_sources))
    else:
        require(not installed_sd.exists(), "SDWebImage source remains installed after migration")
    return result


def validate_source_intake(root: Path) -> dict[str, Any]:
    require((root / PROJECT / "project.pbxproj").is_file(), "expected Xcode project missing", "blocked-input")
    require((root / WORKSPACE / "contents.xcworkspacedata").is_file(), "expected workspace missing", "blocked-input")
    for relative, expected in EXPECTED_SOURCE_HASHES.items():
        require(file_sha256(root / relative) == expected, f"pinned source hash changed: {relative}", "blocked-input")
    podfile = (root / "Podfile").read_text()
    prohibited_ruby = ("post_install", "pre_install", "script_phase", "system(", "`", "%x(", "IO.popen", "Open3")
    require(not any(token in podfile for token in prohibited_ruby), "Podfile contains unreviewed executable Ruby", "blocked-input")
    require(not (root / ".gitmodules").exists(), "source declares submodules", "blocked-input")
    require(not (root / "Package.swift").exists(), "source contains an unreviewed Swift package manifest", "blocked-input")
    for path in root.rglob("*"):
        if ".git" in path.parts:
            continue
        if path.is_symlink():
            raise QualificationError("blocked-input", f"source contains unreviewed symlink: {path.relative_to(root)}")
        if path.is_file() and path.stat().st_size < 1024:
            beginning = path.read_bytes()[:200]
            require(not beginning.startswith(b"version https://git-lfs.github.com/spec/v1"),
                    f"source contains a Git LFS pointer: {path.relative_to(root)}", "blocked-input")
        if path.is_file() and path.stat().st_mode & 0o111:
            raise QualificationError("blocked-input", f"source contains an unreviewed executable: {path.relative_to(root)}")
    license_text = (root / "LICENSE").read_text()
    require("MIT No Attribution" in license_text or "MIT-0" in license_text,
            "source license differs from reviewed MIT-0 license", "blocked-input")
    return {"commit": SOURCE_COMMIT, "license": SOURCE_LICENSE,
            "reviewedFileSHA256": dict(EXPECTED_SOURCE_HASHES),
            "treeSHA256": tree_digest(tree_snapshot(root))}


def parse_lock(text: str) -> dict[str, Any]:
    roots: list[str] = []
    in_deps = False
    for line in text.splitlines():
        if line == "DEPENDENCIES:":
            in_deps = True
            continue
        if in_deps and re.fullmatch(r"[A-Z][A-Z0-9 _-]*:", line):
            break
        if in_deps:
            match = re.match(r"  - ([^ (]+)(?: \(= ([^)]+)\))?", line)
            if match:
                roots.append(match.group(1))
    pods_section = text.split("PODS:\n", 1)[1].split("\nDEPENDENCIES:", 1)[0] if "PODS:\n" in text else ""
    versions = {name: version for name, version in re.findall(r"^  - ([A-Za-z0-9_+/.-]+) \(([^)]+)\)", pods_section, re.MULTILINE)}
    cocoa = re.search(r"COCOAPODS: ([^\n]+)", text)
    checksums_section = text.split("SPEC CHECKSUMS:\n", 1)[1].split("\n\n", 1)[0] if "SPEC CHECKSUMS:\n" in text else ""
    checksums = dict(re.findall(r"^  ([^:]+): ([0-9a-f]{40})$", checksums_section, re.MULTILINE))
    return {"roots": roots, "versions": versions, "checksums": checksums,
            "cocoaPods": cocoa.group(1) if cocoa else None}


def validate_lock(text: str, expected_roots: set[str]) -> dict[str, Any]:
    lock = parse_lock(text)
    require(set(lock["roots"]) == expected_roots, f"unexpected direct Pods roots: {lock['roots']}")
    require(lock["versions"].get("AmazonIVSPlayer") == POD_VERSIONS["AmazonIVSPlayer"], "AmazonIVSPlayer version changed")
    if "SDWebImage" in expected_roots:
        require(lock["versions"].get("SDWebImage") == POD_VERSIONS["SDWebImage"], "SDWebImage version changed")
        require(lock["versions"].get("SDWebImage/Core") == POD_VERSIONS["SDWebImage"], "SDWebImage/Core version changed")
    else:
        require(not any(key == "SDWebImage" or key.startswith("SDWebImage/") for key in lock["versions"]),
                "migrated SDWebImage remains in Pods lock")
    for name in expected_roots:
        require(lock["checksums"].get(name) == PODSPEC_INPUTS[name]["rawSHA1"],
                f"{name} lock checksum differs from reviewed podspec")
    require("EXTERNAL SOURCES:" not in text and "CHECKOUT OPTIONS:" not in text,
            "lockfile gained an external CocoaPods source")
    return lock


def validate_migrated_podfile(before: bytes, after: bytes) -> None:
    declaration = b"    pod 'SDWebImage', '~> 5.0', modular_headers: true\n"
    require(before.count(declaration) == 1, "reviewed SDWebImage Podfile declaration is missing")
    require(before.replace(declaration, b"") == after,
            "Podfile changed beyond removal of the reviewed SDWebImage declaration")


def validate_lock_metadata_normalization(before: str, after: str) -> None:
    def normalize(value: str) -> str:
        return re.sub(r"(?m)^COCOAPODS: .+$", "COCOAPODS: <tool-version>", value)
    require(normalize(before) == normalize(after), "pod install changed more than CocoaPods tool metadata", "blocked-input")
    after_version = parse_lock(after)["cocoaPods"]
    require(after_version in {"1.16.2", COCOAPODS_VERSION}, "unexpected CocoaPods metadata version", "blocked-input")


def normalize_lock_tool_version(text: str) -> str:
    validate_lock(text, set(POD_VERSIONS))
    versions = re.findall(r"(?m)^COCOAPODS: (.+)$", text)
    require(len(versions) == 1 and versions[0] in {"1.16.2", COCOAPODS_VERSION},
            "unexpected or ambiguous CocoaPods lock metadata", "blocked-input")
    normalized = re.sub(r"(?m)^COCOAPODS: .+$", "COCOAPODS: " + COCOAPODS_VERSION, text)
    validate_lock_metadata_normalization(text, normalized)
    return normalized


def _version_requirement_is_exact(value: Any, expected: str) -> bool:
    return value == {"exact": {"_0": expected}}


def _action_name(action: Any) -> tuple[str, Any]:
    require(isinstance(action, dict) and len(action) == 1, "malformed migration action")
    return next(iter(action.items()))


def _validate_actions(actions: Any) -> None:
    require(isinstance(actions, list) and len(actions) == 3, "SDWebImage must have exactly three automatic actions")
    by_name = dict(_action_name(item) for item in actions)
    require(set(by_name) == {"removePod", "addSwiftPackage", "linkProduct"}, "unexpected migration action set")
    require(by_name["removePod"].get("name") == "SDWebImage", "removePod action mismatch")
    add = by_name["addSwiftPackage"]
    require(add.get("repositoryURL") == PACKAGE_URL and _version_requirement_is_exact(add.get("requirement"), "5.18.1"),
            "addSwiftPackage action mismatch")
    link = by_name["linkProduct"]
    require(link == {"repositoryURL": PACKAGE_URL, "productName": "SDWebImage", "targetName": TARGET},
            "linkProduct action mismatch")


def _direct_analysis_candidates(analysis: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    result = []
    for item in analysis.get("candidates", []):
        pod = item.get("pod", {})
        if pod.get("isDirect"):
            result.append(item)
    return result


def _validate_package_mapping(package: Mapping[str, Any]) -> None:
    require(package.get("repositoryURL") == PACKAGE_URL and package.get("products") == ["SDWebImage"],
            "SDWebImage package/product mapping changed")
    require(_version_requirement_is_exact(package.get("versionRequirement"), "5.18.1"),
            "SDWebImage requirement is not exact 5.18.1")
    require(str(package.get("confidence", "")).lower() == "verified", "SDWebImage mapping is not verified")
    languages = {str(value).lower() for value in package.get("supportedConsumerLanguages", [])}
    require(languages == {"swift", "objectivec"}, "SDWebImage consumer-language mapping changed")
    require(package.get("supportedConsumerPlatforms") in (None, []),
            "SDWebImage mapping gained an unreviewed platform rule")


def validate_analysis_and_plan(analysis: Mapping[str, Any], plan: Mapping[str, Any],
                               expected_root: Path | None = None) -> dict[str, Any]:
    project = analysis.get("project", {})
    require(str(project.get("projectPath", "")).endswith("/" + PROJECT)
            and str(project.get("workspacePath", "")).endswith("/" + WORKSPACE),
            "analysis did not use the explicit project/workspace selection")
    require(str(plan.get("projectPath", "")).endswith("/" + PROJECT),
            "plan did not use the explicit project selection")
    if expected_root is not None:
        root = expected_root.resolve(strict=True)
        require(Path(str(project.get("projectPath", ""))).resolve(strict=False) == root / PROJECT
                and Path(str(project.get("workspacePath", ""))).resolve(strict=False) == root / WORKSPACE
                and Path(str(plan.get("projectPath", ""))).resolve(strict=False) == root / PROJECT,
                "analysis or plan selected a same-named path outside the reviewed source copy")
    candidates = _direct_analysis_candidates(analysis)
    require(len(candidates) == 2 and {item.get("pod", {}).get("name") for item in candidates} == set(POD_VERSIONS),
            "analysis direct identity set changed")
    entries = plan.get("entries")
    require(isinstance(entries, list) and len(entries) == 2
            and {e.get("podName") for e in entries} == set(POD_VERSIONS), "plan identity set changed")
    auto_candidates = [item for item in candidates if str(item.get("classification", "")).upper() == "AUTO"]
    auto_entries = [item for item in entries if str(item.get("classification", "")).upper() == "AUTO"]
    require([item["pod"]["name"] for item in auto_candidates] == ["SDWebImage"], "analysis AUTO set is not exactly SDWebImage")
    require([item["podName"] for item in auto_entries] == ["SDWebImage"], "plan AUTO set is not exactly SDWebImage")
    require(auto_candidates[0].get("pod", {}).get("version") == "5.18.1",
            "analysis SDWebImage version changed")
    _validate_package_mapping(auto_candidates[0].get("packageCandidate", {}))
    aws_entry = next(item for item in entries if item["podName"] == "AmazonIVSPlayer")
    retained_actions = aws_entry.get("actions")
    require(str(aws_entry.get("classification", "")).upper() != "AUTO"
            and isinstance(retained_actions, list) and retained_actions
            and all(isinstance(action, dict) and set(action) == {"manual"} for action in retained_actions),
            "retained AmazonIVSPlayer must contain only manual actions")
    entry = auto_entries[0]
    require(entry.get("currentVersion") == "5.18.1" and entry.get("targetName") == TARGET,
            "SDWebImage version or target changed")
    package = entry.get("packageCandidate", {})
    _validate_package_mapping(package)
    profile = entry.get("targetSourceProfile", {})
    require(profile.get("completeness") == "complete"
            and [str(x).lower() for x in profile.get("languages", [])] == ["swift"],
            "target source profile is not Swift")
    _validate_actions(entry.get("actions"))
    return {"auto": ["SDWebImage"], "retained": ["AmazonIVSPlayer"], "target": TARGET, "version": "5.18.1"}


def validate_portable_parity(executable: Mapping[str, Any], portable: Mapping[str, Any], item_key: str,
                             require_marker: bool = True) -> None:
    if require_marker:
        require(portable.get("portableOutput") == {"version": 1},
                f"portable {item_key} lacks the PkgLift portable-output marker")
    def semantic(value: Mapping[str, Any]) -> list[dict[str, Any]]:
        items = value.get(item_key, [])
        clean = []
        for item in items:
            pod = item.get("pod", {})
            package = item.get("packageCandidate") or {}
            clean.append({
                "identity": item.get("podName") or pod.get("name"),
                "currentVersion": item.get("currentVersion") or pod.get("version"),
                "classification": item.get("classification"),
                "reasonDetails": item.get("reasonDetails"),
                "targetName": item.get("targetName"),
                "package": {
                    "repositoryURL": package.get("repositoryURL"),
                    "products": package.get("products"),
                    "versionRequirement": package.get("versionRequirement"),
                    "confidence": package.get("confidence"),
                    "supportedConsumerLanguages": package.get("supportedConsumerLanguages"),
                    "supportedConsumerPlatforms": package.get("supportedConsumerPlatforms"),
                },
                "actions": item.get("actions"),
            })
        return clean
    require(semantic(executable) == semantic(portable), f"portable {item_key} differs semantically")


def _objects(project: Mapping[str, Any], isa: str) -> dict[str, Mapping[str, Any]]:
    return {key: value for key, value in project.get("objects", {}).items() if value.get("isa") == isa}


def protected_project_state(project: Mapping[str, Any]) -> dict[str, Any]:
    objects = project.get("objects", {})
    document_metadata = copy.deepcopy({key: value for key, value in project.items() if key != "objects"})
    projects = {key: copy.deepcopy(value) for key, value in _objects(project, "PBXProject").items()}
    for project_object in projects.values():
        # Adding the reviewed XCRemoteSwiftPackageReference to this field is
        # the only authorized PBXProject mutation. All project metadata and
        # target ownership remains byte-for-byte represented below.
        project_object.pop("packageReferences", None)
    targets = {k: copy.deepcopy(v) for k, v in _objects(project, "PBXNativeTarget").items()}
    sources = copy.deepcopy(_objects(project, "PBXSourcesBuildPhase"))
    resources = copy.deepcopy(_objects(project, "PBXResourcesBuildPhase"))
    configs = copy.deepcopy(_objects(project, "XCBuildConfiguration"))
    file_references = copy.deepcopy(_objects(project, "PBXFileReference"))
    groups = copy.deepcopy(_objects(project, "PBXGroup"))
    nonpackage_build_files = {key: copy.deepcopy(value) for key, value in _objects(project, "PBXBuildFile").items()
                              if not value.get("productRef")}
    framework_membership = {}
    for phase_id, phase in _objects(project, "PBXFrameworksBuildPhase").items():
        framework_membership[phase_id] = [file_id for file_id in phase.get("files", [])
                                          if not objects[file_id].get("productRef")]
    membership: dict[str, Any] = {}
    for phase_id, phase in {**sources, **resources}.items():
        membership[phase_id] = phase
        for build_id in phase.get("files", []):
            build = copy.deepcopy(objects[build_id])
            membership[build_id] = build
            file_id = build.get("fileRef")
            if file_id:
                membership[file_id] = copy.deepcopy(objects[file_id])
    for target in targets.values():
        target.pop("packageProductDependencies", None)
        target["buildPhases"] = [phase for phase in target.get("buildPhases", [])
                                 if objects.get(phase, {}).get("isa") not in {"PBXFrameworksBuildPhase", "PBXShellScriptBuildPhase"}]
    return {"documentMetadata": document_metadata, "projects": projects,
            "targets": targets, "membership": membership, "configurations": configs,
            "fileReferences": file_references, "groups": groups,
            "nonpackageBuildFiles": nonpackage_build_files, "frameworkMembership": framework_membership}


def validate_project_linkage(project: Mapping[str, Any]) -> dict[str, Any]:
    objects = project.get("objects", {})
    all_targets = list(_objects(project, "PBXNativeTarget").values())
    targets = [value for value in all_targets if value.get("name") == TARGET]
    require(len(all_targets) == 1 and len(targets) == 1, "consumer target set changed")
    all_refs = _objects(project, "XCRemoteSwiftPackageReference")
    refs = [value for value in all_refs.values()
            if value.get("repositoryURL", "").rstrip("/").removesuffix(".git").lower() == PACKAGE_URL.removesuffix(".git").lower()]
    require(len(all_refs) == 1 and len(refs) == 1, "SDWebImage must be the only package reference")
    requirement = refs[0].get("requirement", {})
    require(requirement.get("kind") == "exactVersion" and requirement.get("version") == "5.18.1",
            "Xcode package requirement is not exact 5.18.1")
    all_products = _objects(project, "XCSwiftPackageProductDependency")
    product_items = [(key, value) for key, value in all_products.items()
                     if value.get("productName") == "SDWebImage"]
    require(len(all_products) == 1 and len(product_items) == 1,
            "SDWebImage must be the only package product dependency")
    product_id, product = product_items[0]
    reference_items = [(key, value) for key, value in _objects(project, "XCRemoteSwiftPackageReference").items()
                       if value is refs[0]]
    require(len(reference_items) == 1 and product.get("package") == reference_items[0][0],
            "SDWebImage product is not bound to its reviewed package reference")
    dependency_ids = targets[0].get("packageProductDependencies", [])
    require(dependency_ids.count(product_id) == 1, "SDWebImage product is not linked exactly once to Grid Feed")
    root_projects = _objects(project, "PBXProject")
    require(len(root_projects) == 1 and next(iter(root_projects.values())).get("packageReferences") == [reference_items[0][0]],
            "project package reference ownership changed")
    framework_phases = [objects[phase_id] for phase_id in targets[0].get("buildPhases", [])
                        if objects.get(phase_id, {}).get("isa") == "PBXFrameworksBuildPhase"]
    require(len(framework_phases) == 1, "consumer framework phase is missing or ambiguous")
    linked_refs = [objects[file_id].get("productRef") for file_id in framework_phases[0].get("files", [])]
    require([value for value in linked_refs if value] == [product_id],
            "SDWebImage product is not the sole package product in Frameworks")
    build_files = [value for value in _objects(project, "PBXBuildFile").values() if value.get("productRef") == product_id]
    require(len(build_files) == 1, "SDWebImage package product build file is missing or duplicated")
    cp_phases = [objects.get(pid, {}).get("name") for pid in targets[0].get("buildPhases", [])
                 if objects.get(pid, {}).get("isa") == "PBXShellScriptBuildPhase"]
    require(cp_phases.count("[CP] Check Pods Manifest.lock") == 1 and cp_phases.count("[CP] Embed Pods Frameworks") == 1,
            "retained CocoaPods integration phases changed")
    return {"repositoryURL": PACKAGE_URL, "product": "SDWebImage", "linkedCount": 1}


def validate_scheme_listing(document: Mapping[str, Any]) -> None:
    schemes = document.get("workspace", {}).get("schemes") or document.get("project", {}).get("schemes") or []
    require(sum(1 for value in schemes if value == TARGET) == 1, "Grid Feed scheme is missing or ambiguous", "blocked-input")


def validate_installed_podspecs(root: Path, expected_names: set[str] | None = None) -> list[dict[str, Any]]:
    expected_names = expected_names or set(POD_VERSIONS)
    directory = root / "Pods/Local Podspecs"
    paths = sorted(directory.glob("*.podspec.json"))
    require({path.name for path in paths} == {f"{name}.podspec.json" for name in expected_names},
            "installed local podspec set differs from reviewed direct closure", "blocked-input")
    result = []
    for name in expected_names:
        path = directory / f"{name}.podspec.json"
        require(path.is_file() and not path.is_symlink(), f"installed {name} podspec is missing", "blocked-input")
        document = json.loads(path.read_text())
        item = validate_podspec(document, name)
        require(item["canonicalSHA256"] == PODSPEC_INPUTS[name]["canonicalSHA256"],
                f"installed {name} podspec differs from immutable reviewed spec", "blocked-input")
        result.append(item)
    return result


def find_package_resolved(root: Path) -> Path:
    candidates = [path for path in root.rglob("Package.resolved") if ".git" not in path.parts and "Pods" not in path.parts]
    require(len(candidates) == 1, "Package.resolved is missing or ambiguous")
    return candidates[0]


def validate_package_resolved(document: Mapping[str, Any]) -> dict[str, Any]:
    pins = document.get("pins") or document.get("object", {}).get("pins") or []
    require(isinstance(pins, list) and len(pins) == 1, "resolved package pin set changed")
    matches = []
    for pin in pins:
        location = pin.get("location") or pin.get("repositoryURL") or ""
        if location.rstrip("/").removesuffix(".git").lower() == PACKAGE_URL.removesuffix(".git").lower():
            matches.append(pin)
    require(len(matches) == 1, "SDWebImage resolved pin missing or duplicated")
    state = matches[0].get("state", {})
    require(state.get("version") == "5.18.1" and state.get("revision") == PACKAGE_REVISION,
            "SDWebImage did not resolve to reviewed exact revision")
    return {"version": "5.18.1", "revision": PACKAGE_REVISION}


def validate_privacy_resource_symlinks(checkout: Path) -> dict[str, Any]:
    links = {path.relative_to(checkout).as_posix(): path
             for path in checkout.rglob("PrivacyInfo.xcprivacy") if path.is_symlink()}
    require(set(links) == set(PRIVACY_RESOURCE_SYMLINKS),
            "reviewed SDWebImage privacy resource symlink inventory changed", "blocked-input")
    for relative in PRIVACY_RESOURCE_SYMLINKS:
        link = links[relative]
        target_bytes = os.readlink(link).encode()
        require(target_bytes == b"../../WebImage/PrivacyInfo.xcprivacy"
                and sha256_bytes(target_bytes) == PRIVACY_SYMLINK_SHA256,
                f"SDWebImage privacy resource symlink bytes changed: {relative}", "blocked-input")
        target = link.resolve(strict=True)
        require(_under(target, checkout.resolve())
                and target.relative_to(checkout.resolve()).as_posix() == "WebImage/PrivacyInfo.xcprivacy"
                and file_sha256(target) == PRIVACY_RESOURCE_SHA256,
                f"SDWebImage privacy resource target/hash changed: {relative}", "blocked-input")
    return {
        "privacyResourceSHA256": PRIVACY_RESOURCE_SHA256,
        "privacyResourcePath": PRIVACY_RESOURCE_SYMLINKS[0],
        "reviewedPrivacyResourceSymlinks": list(PRIVACY_RESOURCE_SYMLINKS),
    }


def validate_swiftpm_checkout(checkout: Path, run_git) -> dict[str, Any]:
    require(checkout.is_dir() and not checkout.is_symlink(), "SDWebImage checkout is missing")
    head = run_git(checkout, ["rev-parse", "HEAD"]).strip()
    status = run_git(checkout, ["status", "--porcelain", "--untracked-files=all"])
    require(head == PACKAGE_REVISION and not status, "SDWebImage checkout revision or cleanliness mismatch")
    manifest = checkout / "Package.swift"
    require(manifest.is_file(), "SDWebImage Package.swift missing")
    text = manifest.read_text()
    require(file_sha256(manifest) == PACKAGE_MANIFEST_SHA256,
            "resolved SDWebImage manifest differs from pre-resolution input", "blocked-input")
    validate_package_manifest_bytes(manifest.read_bytes())
    require(not any(path.name in {"Plugins", "Plugin"} for path in checkout.rglob("*")),
            "SDWebImage checkout contains a plugin directory", "blocked-input")
    require(not (checkout / ".gitmodules").exists(), "SDWebImage checkout declares submodules", "blocked-input")
    privacy_evidence = validate_privacy_resource_symlinks(checkout)
    require("PrivacyInfo.xcprivacy" in text, "SDWebImage manifest no longer declares reviewed privacy resource", "blocked-input")
    indexed = run_git(checkout, ["ls-files", "-s"]).splitlines()
    executable_entries = []
    for line in indexed:
        match = re.match(r"^(100755) ([0-9a-f]{40}) \d+\t(.+)$", line)
        if match:
            executable_entries.append((match.group(3), match.group(2)))
    expected_executables = {
        "SDWebImage_logo.png": "ee2d81f34ce7299b384b26533426c6c3bb9d02d3",
        "Scripts/build-frameworks.sh": "82a7dd321c399b046548013b0dd48a9fcec86897",
        "Scripts/create-xcframework.sh": "660b6d64dcc264975afb9d5bd3a1d30e31beaa8c",
    }
    require(dict(executable_entries) == expected_executables,
            "SDWebImage executable-file inventory changed", "blocked-input")
    require(file_sha256(checkout / "Scripts/build-frameworks.sh")
            == "bef6701a528ff71d4be9f761b4234d419353f732c116b51668260cb0dc10614e"
            and file_sha256(checkout / "Scripts/create-xcframework.sh")
            == "064662c792e8505c4938e706c64bcc7cea600db280a7951112be1386673b27fc",
            "unreferenced SDWebImage executable script bytes changed", "blocked-input")
    return {"revision": head, "manifestSHA256": file_sha256(manifest),
            **privacy_evidence,
            "unreferencedExecutables": sorted(expected_executables)}


def validate_built_privacy_resource(derived: Path) -> dict[str, Any]:
    candidates = [path for app in (derived / "Build/Products/Debug-iphonesimulator").glob("*.app")
                  for path in app.glob("**/SDWebImage_SDWebImage.bundle/PrivacyInfo.xcprivacy")]
    matches = [path for path in candidates if path.is_file() and not path.is_symlink()
               and file_sha256(path) == PRIVACY_RESOURCE_SHA256]
    require(len(candidates) == 1 and len(matches) == 1,
            "final app does not contain exactly one byte-matching SDWebImage privacy resource")
    return {"sha256": PRIVACY_RESOURCE_SHA256, "matchingCopiesInApp": 1,
            "resourceBundle": "SDWebImage_SDWebImage.bundle"}


def redact(value: Any, private_roots: Iterable[Path] = ()) -> Any:
    roots = sorted((str(path) for path in private_roots), key=len, reverse=True)
    if isinstance(value, dict):
        return {str(key): redact(child, private_roots) for key, child in value.items()}
    if isinstance(value, list):
        return [redact(child, private_roots) for child in value]
    if not isinstance(value, str):
        return value
    text = value
    for root in roots:
        text = text.replace(root, "<private>")
    text = re.sub(r"(https?://)[^/@\s]+:[^/@\s]+@", r"\1<redacted>@", text)
    text = re.sub(r"/Users/[^/\s]+", "/Users/<redacted>", text)
    return text


def command_environment(environment: Mapping[str, str]) -> dict[str, str]:
    clean = {key: value for key, value in environment.items() if not key.startswith("GIT_")}
    clean.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_SYSTEM="/dev/null", GIT_CONFIG_GLOBAL="/dev/null",
                 GIT_CONFIG_COUNT="0", GIT_LFS_SKIP_SMUDGE="1", GIT_TERMINAL_PROMPT="0",
                 GIT_ASKPASS="/usr/bin/false")
    return clean


class Runner:
    def __init__(self, contract: Mapping[str, Any], jobs: int):
        self.binary = Path(contract["binary"])
        self.output = Path(contract["output"])
        self.private = self.output / "private"
        self.report = self.output / "report"
        self.jobs = jobs
        self.commands: list[dict[str, Any]] = []
        self.redaction_roots = [self.private, self.output, Path(contract["runnerTemp"]), self.binary.parent, Path.home()]
        self.sd_source_reference: Path | None = None
        self.amazon_payload_tree: dict[str, Any] = {}

    def execute(self, label: str, command: list[Any], cwd: Path | None = None, timeout: int = 300,
                expect_json: bool = False, outcome: str = "failed-migration") -> Any:
        argv = [str(value) for value in command]
        stdout = self.private / "logs" / f"{len(self.commands) + 1:02d}-{label}.out"
        stderr = self.private / "logs" / f"{len(self.commands) + 1:02d}-{label}.err"
        stdout.parent.mkdir(parents=True, exist_ok=True)
        started = time.monotonic()
        wrapper = [sys.executable, ROOT / "Scripts/run-with-timeout.py", "--seconds", timeout]
        if cwd:
            wrapper += ["--cwd", cwd]
        wrapper += ["--stdout", stdout, "--stderr", stderr, "--", *argv]
        completed = subprocess.run([str(value) for value in wrapper], check=False,
                                   env=command_environment(os.environ))
        code = completed.returncode
        duration = round(time.monotonic() - started, 3)
        stdout_bytes = stdout.read_bytes() if stdout.exists() else b""
        stderr_bytes = stderr.read_bytes() if stderr.exists() else b""
        record = {"label": label, "argv": redact(argv, self.redaction_roots), "exitCode": code,
                  "durationSeconds": duration, "stdoutSHA256": sha256_bytes(stdout_bytes),
                  "stderrSHA256": sha256_bytes(stderr_bytes), "stdoutBytes": len(stdout_bytes),
                  "stderrBytes": len(stderr_bytes)}
        if code and stderr_bytes:
            # Keep only bounded stderr. Compiler stdout can contain source excerpts
            # and therefore remains private even when a build fails.
            tail = stderr_bytes[-4096:].decode("utf-8", errors="replace")
            record["redactedStderrTail"] = redact(tail, self.redaction_roots)
        if code and stdout_bytes and label in POD_INSTALL_DIAGNOSTIC_LABELS:
            # CocoaPods reports many actionable failures on stdout. Restrict
            # this exception to install commands; compiler stdout can contain
            # source excerpts and always remains private.
            tail = stdout_bytes[-4096:].decode("utf-8", errors="replace")
            record["redactedStdoutTail"] = redact(tail, self.redaction_roots)
        self.commands.append(record)
        if code == 124:
            raise QualificationError(outcome, f"{label} timed out after {timeout}s")
        if code:
            raise QualificationError(outcome, f"{label} exited {code}; private log retained")
        if expect_json:
            try:
                return json.loads(stdout.read_text())
            except ValueError as error:
                raise QualificationError(outcome, f"{label} did not emit valid JSON") from error
        return stdout.read_text(errors="replace")

    def git(self, root: Path, args: list[str], **kwargs) -> str:
        return self.execute("git-" + args[0], ["git", "-C", root, *args], **kwargs)

    def clone(self, destination: Path, label: str) -> dict[str, Any]:
        destination.mkdir()
        self.execute(f"{label}-init", ["git", "-c", "init.templateDir=", "init", "--quiet", destination])
        self.execute(f"{label}-hooks", ["git", "-C", destination, "config", "core.hooksPath", "/dev/null"])
        self.execute(f"{label}-credentials", ["git", "-C", destination, "config", "credential.helper", ""])
        self.execute(f"{label}-remote", ["git", "-C", destination, "remote", "add", "origin", REPOSITORY])
        self.execute(f"{label}-fetch", ["git", "-C", destination, "-c", "credential.helper=", "fetch", "--quiet",
                                        "--depth", "1", "--no-tags", "origin", SOURCE_COMMIT], timeout=300,
                     outcome="blocked-input")
        self.execute(f"{label}-checkout", ["git", "-C", destination, "checkout", "--quiet", "--detach", "FETCH_HEAD"])
        self.execute(f"{label}-remove-remote", ["git", "-C", destination, "remote", "remove", "origin"])
        head = self.git(destination, ["rev-parse", "HEAD"]).strip()
        status = self.git(destination, ["status", "--porcelain", "--untracked-files=all"])
        remotes = self.git(destination, ["remote"])
        require(head == SOURCE_COMMIT and not status and not remotes, f"{label} source checkout failed provenance/cleanliness", "blocked-input")
        return validate_source_intake(destination)

    def clone_sdwebimage_reference(self) -> dict[str, Any]:
        destination = self.private / "inputs/sdwebimage-source"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.mkdir()
        self.execute("sd-source-init", ["git", "-c", "init.templateDir=", "init", "--quiet", destination])
        self.execute("sd-source-hooks", ["git", "-C", destination, "config", "core.hooksPath", "/dev/null"])
        self.execute("sd-source-remote", ["git", "-C", destination, "remote", "add", "origin", PACKAGE_GIT_URL])
        self.execute("sd-source-fetch", ["git", "-C", destination, "-c", "credential.helper=", "fetch", "--quiet",
                                         "--depth", "1", "--no-tags", "origin", PACKAGE_REVISION],
                     timeout=300, outcome="blocked-input")
        self.execute("sd-source-checkout", ["git", "-C", destination, "checkout", "--quiet", "--detach", "FETCH_HEAD"])
        self.execute("sd-source-remove-remote", ["git", "-C", destination, "remote", "remove", "origin"])
        evidence = validate_swiftpm_checkout(destination, lambda path, args: self.git(path, args))
        selected = selected_sdwebimage_sources(destination)
        self.sd_source_reference = destination
        return {**evidence, "selectedCocoaPodsSourceCount": len(selected),
                "selectedCocoaPodsTreeSHA256": canonical_json_sha256(selected)}

    def pbx_json(self, root: Path, label: str) -> dict[str, Any]:
        raw = self.execute(label, ["plutil", "-convert", "json", "-o", "-", root / PROJECT / "project.pbxproj"])
        try:
            return json.loads(raw)
        except ValueError as error:
            raise QualificationError("failed-safety", f"{label} project conversion invalid") from error

    def validate_cocoapods(self, root: Path, label: str) -> dict[str, Any]:
        evidence = self.execute(label, ["ruby", ROOT / "Scripts/validate-real-project-cocoapods.rb", root],
                                cwd=ROOT, timeout=120, expect_json=True, outcome="blocked-input")
        require(evidence.get("status") == "passed", "generated CocoaPods execution inputs were not approved", "blocked-input")
        return evidence

    def pod_setup(self, root: Path, label: str) -> tuple[str, dict[str, Any], dict[str, Any]]:
        original_lock = (root / "Podfile.lock").read_text()
        # Deployment mode compares the tool version too. Normalize only the
        # reviewed metadata before invoking it; dependency locks stay identical.
        (root / "Podfile.lock").write_text(normalize_lock_tool_version(original_lock))
        self.execute(label, ["pod", "install", "--deployment"], cwd=root, timeout=900,
                     outcome="inconclusive-baseline" if label.startswith("baseline") else "blocked-input")
        lock_text = (root / "Podfile.lock").read_text()
        validate_lock_metadata_normalization(original_lock, lock_text)
        tracked_changes = self.git(root, ["diff", "--name-only", "HEAD"]).splitlines()
        untracked = self.git(root, ["ls-files", "--others", "--exclude-standard"]).splitlines()
        require(set(tracked_changes) <= {"Podfile.lock"} and not untracked,
                "CocoaPods setup changed source-tracked files beyond lock metadata", "blocked-input")
        lock = validate_lock(lock_text, set(POD_VERSIONS))
        require((root / "Pods/Manifest.lock").read_bytes() == (root / "Podfile.lock").read_bytes(),
                "Pods Manifest.lock differs from Podfile.lock", "blocked-input")
        installed = validate_installed_podspecs(root)
        payloads = validate_installed_dependency_payloads(root, self.sd_source_reference,
                                                          self.amazon_payload_tree, include_sd=True)
        project = self.pbx_json(root, label + "-project")
        phases = self.validate_cocoapods(root, label + "-cocoapods-execution-inputs")
        return lock_text, project, {"lock": lock, "installedPodspecs": installed,
                                    "installedPayloads": payloads, "generatedPhases": phases}

    def environment_gate(self) -> dict[str, Any]:
        captured = self.execute("environment", [sys.executable, ROOT / "Scripts/capture-environment.py"],
                                timeout=120, expect_json=True, outcome="blocked-input")
        require(captured.get("captureStatus") == "complete", "environment capture is incomplete", "blocked-input")
        require(captured.get("repository", {}).get("commit") == os.environ.get("GITHUB_SHA")
                and captured.get("repository", {}).get("trackedChanges") is False,
                "PkgLift source checkout differs from workflow SHA", "blocked-input")
        require(captured.get("system", {}).get("machine") == "arm64"
                and str(captured.get("system", {}).get("macOS", {}).get("version", "")).startswith("15."),
                "runner must be macOS 15 on arm64", "blocked-input")
        probes = captured.get("commands", {})
        require(probes.get("xcodebuildVersion", {}).get("versionOutput", [None])[0] == "Xcode 16.4",
                "Xcode must be exactly 16.4", "blocked-input")
        require(probes.get("cocoaPodsVersion", {}).get("versionOutput") == [COCOAPODS_VERSION],
                "CocoaPods must be exactly 1.17.0", "blocked-input")
        captured["rubyVersion"] = self.execute("ruby-version", ["ruby", "--version"], timeout=60).strip()
        captured["pkgLiftVersion"] = self.execute("pkglift-version", [self.binary, "version"], timeout=60).strip()
        return captured

    def fetch_podspecs(self) -> list[dict[str, Any]]:
        evidence = []
        for name, source in PODSPEC_INPUTS.items():
            request = urllib.request.Request(source["url"], headers={"User-Agent": "PkgLift-G3-qualification/1"})
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    raw = response.read(2 * 1024 * 1024)
                    require(response.read(1) == b"", f"{name} podspec exceeds size limit", "blocked-input")
            except OSError as error:
                raise QualificationError("blocked-input", f"unable to fetch reviewed {name} podspec") from error
            _, item = validate_public_podspec_bytes(name, raw)
            evidence.append({**item, "url": source["url"], "rawSHA256": source["rawSHA256"]})
        return evidence

    def fetch_static_dependency_inputs(self) -> dict[str, Any]:
        podspecs = self.fetch_podspecs()
        tag_line = self.execute("sdwebimage-tag-binding",
                                ["git", "-c", "credential.helper=", "ls-remote", "--refs", PACKAGE_GIT_URL,
                                 "refs/tags/5.18.1"], timeout=120, outcome="blocked-input").strip()
        require(tag_line == f"{PACKAGE_REVISION}\trefs/tags/5.18.1",
                "SDWebImage 5.18.1 tag no longer binds to reviewed commit", "blocked-input")
        manifest_request = urllib.request.Request(PACKAGE_MANIFEST_URL,
                                                  headers={"User-Agent": "PkgLift-G3-qualification/1"})
        try:
            with urllib.request.urlopen(manifest_request, timeout=30) as response:
                manifest = response.read(1024 * 1024)
                require(response.read(1) == b"", "SDWebImage manifest exceeds size limit", "blocked-input")
        except OSError as error:
            raise QualificationError("blocked-input", "unable to fetch reviewed SDWebImage manifest") from error
        manifest_evidence = validate_package_manifest_bytes(manifest)
        source_evidence = self.clone_sdwebimage_reference()
        license_request = urllib.request.Request(AMAZON_LICENSE_URL,
                                                 headers={"User-Agent": "PkgLift-G3-qualification/1"})
        try:
            with urllib.request.urlopen(license_request, timeout=30) as response:
                license_bytes = response.read(1024 * 1024)
                require(response.read(1) == b"", "Amazon license exceeds size limit", "blocked-input")
        except OSError as error:
            raise QualificationError("blocked-input", "unable to fetch reviewed Amazon license") from error
        require(sha256_bytes(license_bytes) == AMAZON_LICENSE_SHA256,
                "mutable Amazon license bytes changed", "blocked-input")
        archive_path = self.private / "inputs/AmazonIVSPlayer-1.40.0.tgz"
        archive_path.parent.mkdir(parents=True, exist_ok=True)
        request = urllib.request.Request(AMAZON_ARCHIVE_URL,
                                         headers={"User-Agent": "PkgLift-G3-qualification/1"})
        try:
            digest = hashlib.sha256()
            size = 0
            with urllib.request.urlopen(request, timeout=60) as response, archive_path.open("wb") as output:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    size += len(chunk)
                    require(size <= 64 * 1024 * 1024, "Amazon archive download exceeds size limit", "blocked-input")
                    digest.update(chunk)
                    output.write(chunk)
        except OSError as error:
            raise QualificationError("blocked-input", "unable to fetch reviewed Amazon archive") from error
        require(digest.hexdigest() == AMAZON_ARCHIVE_SHA256, "Amazon archive download digest changed", "blocked-input")
        archive = inspect_amazon_archive(archive_path)
        self.amazon_payload_tree = archive.pop("_payloadTree")
        return {"podspecs": podspecs, "swiftPackageTagRevision": PACKAGE_REVISION,
                "swiftPackageManifest": manifest_evidence, "swiftPackageSource": source_evidence,
                "amazonArchive": archive, "amazonLicenseSHA256": AMAZON_LICENSE_SHA256}

    def build(self, root: Path, derived: Path, label: str, outcome: str) -> None:
        self.execute(label, ["xcodebuild", "-workspace", root / WORKSPACE, "-scheme", TARGET,
                             "-configuration", "Debug", "-sdk", "iphonesimulator",
                             "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", derived,
                             "-jobs", self.jobs, "CODE_SIGNING_ALLOWED=NO", "build"], timeout=1800, outcome=outcome)

    def run(self, contract: Mapping[str, Any]) -> dict[str, Any]:
        self.output.mkdir()
        self.private.mkdir()
        self.report.mkdir()
        summary: dict[str, Any] = {
            "schemaVersion": 1, "case": "aws-grid-feed", "status": "failed-safety",
            "source": {"repository": REPOSITORY, "commit": SOURCE_COMMIT, "license": SOURCE_LICENSE},
            "selection": {"project": PROJECT, "workspace": WORKSPACE, "scheme": TARGET},
            "artifact": contract["artifact"],
            "implementation": {
                "runnerSHA256": file_sha256(Path(__file__)),
                "cocoaPodsValidatorSHA256": file_sha256(ROOT / "Scripts/validate-real-project-cocoapods.rb"),
                "executionIntakeSHA256": file_sha256(
                    ROOT / "Documentation/Evidence/RealProjectQualification-1.0/execution-intake.json"
                ),
            },
        }
        try:
            summary["environment"] = self.environment_gate()
            (self.report / "environment.json").write_text(
                json.dumps(redact(summary["environment"], self.redaction_roots), indent=2, sort_keys=True) + "\n"
            )
            summary["dependencyIntake"] = self.fetch_static_dependency_inputs()
            baseline = self.private / "baseline-source"
            migration = self.private / "migration-source"
            baseline_source = self.clone(baseline, "baseline")
            migration_source = self.clone(migration, "migration")
            require(baseline_source == migration_source, "independent source copies differ", "blocked-input")
            original_baseline = tree_snapshot(baseline)
            original_migration = tree_snapshot(migration)
            summary["source"].update(migration_source)

            _, baseline_project, baseline_setup = self.pod_setup(baseline, "baseline-pod-install")
            schemes = self.execute("baseline-scheme-list", ["xcodebuild", "-list", "-json", "-workspace", baseline / WORKSPACE],
                                   timeout=120, expect_json=True, outcome="inconclusive-baseline")
            validate_scheme_listing(schemes)
            self.validate_cocoapods(baseline, "pre-baseline-build-cocoapods-execution-inputs")
            self.build(baseline, self.private / "baseline-derived", "baseline-build", "inconclusive-baseline")
            baseline_checkpoint = tree_snapshot(baseline)
            summary["baseline"] = {"status": "passed", "sourceTreeSHA256": tree_digest(original_baseline),
                                   "setup": baseline_setup}

            setup_before = tree_snapshot(migration)
            setup_lock, setup_project, migration_setup = self.pod_setup(migration, "migration-pod-install")
            setup_after = tree_snapshot(migration)
            setup_changes = validate_dependency_only_delta(setup_before, setup_after)
            self.git(migration, ["add", "-A"])
            staged = self.git(migration, ["diff", "--cached", "--name-only"]).splitlines()
            require(set(staged) <= {"Podfile.lock"},
                    "CocoaPods setup changed tracked files beyond reviewed lock metadata", "blocked-input")
            if staged:
                self.execute("migration-setup-commit", ["git", "-C", migration, "-c", "user.name=PkgLift Qualification",
                                                        "-c", "user.email=qualification@invalid", "commit", "--quiet",
                                                        "-m", "Record reviewed CocoaPods setup metadata"])
            setup_commit = self.git(migration, ["rev-parse", "HEAD"]).strip()
            require(not self.git(migration, ["status", "--porcelain", "--untracked-files=all"]), "migration setup is dirty")
            exclude_generated_plan(migration, ".pkglift/plan.json")
            common = ["--path", migration, "--project", PROJECT, "--workspace", WORKSPACE, "--no-color"]
            analysis = self.execute("analysis-executable", [self.binary, "analyze", *common, "--json"], expect_json=True)
            portable_analysis = self.execute("analysis-portable", [self.binary, "analyze", *common, "--portable-json"], expect_json=True)
            plan_stdout = self.execute("plan-executable", [self.binary, "plan", *common, "--json"], expect_json=True)
            plan_path = migration / ".pkglift/plan.json"
            require(plan_path.is_file(), "PkgLift plan file is missing")
            first_plan = json.loads(plan_path.read_text())
            require(plan_stdout == first_plan, "executable plan stdout differs from its saved plan")
            portable_plan = self.execute("plan-portable", [self.binary, "plan", *common, "--portable-json"], expect_json=True)
            plan = json.loads(plan_path.read_text())
            plan_evidence = validate_analysis_and_plan(analysis, plan, migration)
            validate_analysis_and_plan(analysis, first_plan, migration)
            validate_portable_parity(analysis, portable_analysis, "candidates")
            validate_portable_parity(plan, portable_plan, "entries")
            validate_portable_parity(first_plan, plan, "entries", require_marker=False)
            (self.report / "portable-analysis.json").write_text(
                json.dumps(redact(portable_analysis, self.redaction_roots), indent=2, sort_keys=True) + "\n"
            )
            (self.report / "portable-plan.json").write_text(
                json.dumps(redact(portable_plan, self.redaction_roots), indent=2, sort_keys=True) + "\n"
            )
            require(not self.git(migration, ["status", "--porcelain", "--untracked-files=all"]),
                    "planning dirtied migration source outside excluded plan")
            index_before_dry = self.git(migration, ["ls-files", "--stage", "-z"])
            before_dry = tree_snapshot(migration)
            setup_podfile = (migration / "Podfile").read_bytes()
            dry_run_output = self.execute("migration-dry-run", [self.binary, "migrate", *common])
            validate_dry_run_output(dry_run_output)
            validate_dry_run(before_dry, tree_snapshot(migration))
            require(self.git(migration, ["ls-files", "--stage", "-z"]) == index_before_dry
                    and not self.git(migration, ["status", "--porcelain", "--untracked-files=all"]),
                    "PkgLift dry run changed Git index or worktree state")
            self.execute("migration-apply", [self.binary, "migrate", *common, "--apply"])
            validate_migrated_podfile(setup_podfile, (migration / "Podfile").read_bytes())
            after_apply = tree_snapshot(migration)
            apply_changes = validate_dependency_only_delta(setup_after, after_apply)
            require(protected_project_state(self.pbx_json(migration, "post-apply-project")) == protected_project_state(setup_project),
                    "source/resource membership or build settings changed during apply")
            self.execute("post-migration-pod-install", ["pod", "install", "--clean-install"], cwd=migration,
                         timeout=900, outcome="failed-migration")
            final_lock_text = (migration / "Podfile.lock").read_text()
            final_lock = validate_lock(final_lock_text, {"AmazonIVSPlayer"})
            require((migration / "Pods/Manifest.lock").read_bytes() == (migration / "Podfile.lock").read_bytes(),
                    "final Pods manifest differs from lock")
            amazon_spec = migration / "Pods/Local Podspecs/AmazonIVSPlayer.podspec.json"
            require(amazon_spec.is_file(), "retained Amazon podspec missing")
            retained_podspec = validate_installed_podspecs(migration, {"AmazonIVSPlayer"})[0]
            retained_payload = validate_installed_dependency_payloads(
                migration, self.sd_source_reference, self.amazon_payload_tree, include_sd=False
            )
            final_project = self.pbx_json(migration, "final-project")
            phases = self.validate_cocoapods(migration, "final-cocoapods-execution-inputs")
            require(protected_project_state(final_project) == protected_project_state(setup_project),
                    "protected project state differs after CocoaPods refresh")
            linkage = validate_project_linkage(final_project)
            verify = self.execute("structural-verification", [self.binary, "verify", *common, "--json"], expect_json=True)
            checks = verify.get("checks", [])
            require(checks and all(check.get("passed") is True for check in checks), "PkgLift structural verification failed")
            (self.report / "structural-verification.json").write_text(
                json.dumps(redact(verify, self.redaction_roots), indent=2, sort_keys=True) + "\n"
            )
            final_derived = self.private / "final-derived"
            self.execute("resolve-packages", ["xcodebuild", "-resolvePackageDependencies", "-workspace", migration / WORKSPACE,
                                              "-scheme", TARGET, "-derivedDataPath", final_derived], timeout=900)
            pin = validate_package_resolved(json.loads(find_package_resolved(migration).read_text()))
            checkout = final_derived / "SourcePackages/checkouts/SDWebImage"
            checkout_evidence = validate_swiftpm_checkout(checkout, lambda path, args: self.git(path, args))
            # Phase and dependency audits deliberately precede the first post-migration build.
            self.validate_cocoapods(migration, "pre-final-build-cocoapods-execution-inputs")
            self.build(migration, final_derived, "final-build", "failed-migration")
            built_privacy = validate_built_privacy_resource(final_derived)
            final_tree = tree_snapshot(migration)
            final_changes = validate_dependency_only_delta(setup_after, final_tree)
            require(tree_snapshot(baseline) == baseline_checkpoint,
                    "independent baseline copy changed after its recorded checkpoint")
            summary.update({
                "status": "passed-migration",
                "migration": {
                    "setupCommit": setup_commit,
                    "setupChangedPaths": setup_changes,
                    "applyChangedPaths": apply_changes,
                    "finalChangedPaths": final_changes,
                    "plan": plan_evidence,
                    "retainedLock": {"roots": final_lock["roots"], "versions": {"AmazonIVSPlayer": "1.40.0"}},
                    "retainedPodspec": retained_podspec,
                    "retainedPayload": retained_payload,
                    "generatedPhases": phases,
                    "linkage": linkage,
                    "resolved": pin,
                    "checkout": checkout_evidence,
                    "builtPrivacyResource": built_privacy,
                    "dryRunUnchanged": True,
                    "preApplyIndexSHA256": sha256_bytes(index_before_dry.encode()),
                    "protectedProjectStateUnchanged": True,
                    "freshFinalBuild": True,
                    "originalTreeSHA256": tree_digest(original_migration),
                    "setupTreeSHA256": tree_digest(setup_after),
                    "finalTreeSHA256": tree_digest(final_tree),
                },
            })
        except QualificationError as error:
            summary["status"] = error.outcome
            summary["failure"] = str(error)
            raise
        except Exception as error:
            summary["status"] = "failed-safety"
            summary["failure"] = f"unexpected runner error: {type(error).__name__}"
            raise QualificationError("failed-safety", summary["failure"]) from error
        finally:
            summary["commands"] = self.commands
            portable = redact(summary, self.redaction_roots)
            (self.report / "summary.json").write_text(json.dumps(portable, indent=2, sort_keys=True) + "\n")
        return summary


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pkglift", required=True, type=Path, help="absolute verified PkgLift executable")
    parser.add_argument("--output", required=True, type=Path, help="new directory below RUNNER_TEMP")
    parser.add_argument("--jobs", type=int, default=2, choices=range(1, 5), metavar="1..4")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        contract = validate_runtime_contract(args.pkglift, args.output, os.environ)
    except QualificationError as error:
        print(f"blocked before execution: {error}", file=sys.stderr)
        return 2
    runner = Runner(contract, args.jobs)
    try:
        runner.run(contract)
    except QualificationError as error:
        print(f"qualification outcome {error.outcome}: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": "passed-migration", "report": str(args.output / "report")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
