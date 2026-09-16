#!/usr/bin/env python3
"""Capture privacy-bounded environment metadata for qualification records."""

from __future__ import annotations

import json
import os
import platform
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Sequence


SCHEMA_VERSION = 1
COMMAND_TIMEOUT_SECONDS = 15
STATUSES = {"passed", "unavailable", "failed", "timedOut"}
FULL_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
MACOS_VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+){1,2}$")
BUILD_RE = re.compile(r"^[A-Za-z0-9.]+$")
XCODE_LINE_RE = re.compile(
    r"^(?:Xcode [0-9]+(?:\.[0-9]+){0,2}(?: (?:beta|Release Candidate) [0-9]+)?|Build version [A-Za-z0-9.]+)$"
)
SWIFT_LINE_RE = re.compile(
    r"^(?:Apple )?Swift version [A-Za-z0-9.+-]+(?: \([A-Za-z0-9 .+_-]+\))?$"
    r"|^Target: [A-Za-z0-9_.-]+$"
    r"|^swift-driver version: [A-Za-z0-9.+-]+(?: [A-Za-z0-9 .+_-]+)?$"
)
POD_VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+){1,3}(?:[.-][A-Za-z0-9]+)*$")
SDK_VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+){1,2}$")
MACHINE_RE = re.compile(r"^[A-Za-z0-9_.-]+$")

Runner = Callable[[Sequence[str], Path, int], subprocess.CompletedProcess[str]]
Resolver = Callable[[str], str | None]


def _run(command: Sequence[str], cwd: Path, timeout: int) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment["LC_ALL"] = "C"
    environment["LANG"] = "C"
    return subprocess.run(
        list(command),
        cwd=cwd,
        env=environment,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def _result(status: str, exit_code: int | None, output: list[str] | None = None) -> dict[str, object]:
    if status not in STATUSES:
        raise ValueError(f"unsupported probe status: {status}")
    return {
        "status": status,
        "exitCode": exit_code,
        "versionOutput": output or [],
    }


def _allowed_lines(stdout: str, pattern: re.Pattern[str]) -> list[str] | None:
    lines = [line.strip() for line in stdout.splitlines() if line.strip()]
    if not lines or len(lines) > 8:
        return None
    if any(len(line) > 200 or pattern.fullmatch(line) is None for line in lines):
        return None
    return lines


def _probe(
    executable: str,
    arguments: Sequence[str],
    allowed_pattern: re.Pattern[str],
    repo_root: Path,
    runner: Runner,
    resolver: Resolver,
) -> dict[str, object]:
    resolved = resolver(executable)
    if resolved is None:
        return _result("unavailable", None)

    try:
        completed = runner([resolved, *arguments], repo_root, COMMAND_TIMEOUT_SECONDS)
    except FileNotFoundError:
        return _result("unavailable", None)
    except subprocess.TimeoutExpired:
        return _result("timedOut", None)
    except OSError:
        return _result("failed", None)

    exit_code = completed.returncode
    if exit_code != 0:
        return _result("failed", exit_code)

    output = _allowed_lines(completed.stdout, allowed_pattern)
    if output is None:
        return _result("failed", exit_code)
    return _result("passed", exit_code, output)


def _repository(repo_root: Path, runner: Runner, resolver: Resolver) -> dict[str, object]:
    git = resolver("git")
    if git is None:
        return {"status": "unavailable", "commit": None, "trackedChanges": None}

    try:
        revision = runner([git, "rev-parse", "--verify", "HEAD"], repo_root, COMMAND_TIMEOUT_SECONDS)
        changes = runner(
            [git, "diff", "--quiet", "--ignore-submodules=none", "HEAD", "--"],
            repo_root,
            COMMAND_TIMEOUT_SECONDS,
        )
    except FileNotFoundError:
        return {"status": "unavailable", "commit": None, "trackedChanges": None}
    except subprocess.TimeoutExpired:
        return {"status": "timedOut", "commit": None, "trackedChanges": None}
    except OSError:
        return {"status": "failed", "commit": None, "trackedChanges": None}

    commit = revision.stdout.strip()
    if revision.returncode != 0 or FULL_SHA_RE.fullmatch(commit) is None:
        return {"status": "failed", "commit": None, "trackedChanges": None}
    if changes.returncode not in (0, 1):
        return {"status": "failed", "commit": commit, "trackedChanges": None}
    return {
        "status": "passed",
        "commit": commit,
        "trackedChanges": changes.returncode == 1,
    }


def _macos(repo_root: Path, runner: Runner, resolver: Resolver) -> dict[str, object]:
    sw_vers = resolver("sw_vers")
    if platform.system() != "Darwin" or sw_vers is None:
        return {"status": "unavailable", "version": None, "build": None}

    try:
        version_result = runner(
            [sw_vers, "-productVersion"], repo_root, COMMAND_TIMEOUT_SECONDS
        )
        build_result = runner(
            [sw_vers, "-buildVersion"], repo_root, COMMAND_TIMEOUT_SECONDS
        )
    except FileNotFoundError:
        return {"status": "unavailable", "version": None, "build": None}
    except subprocess.TimeoutExpired:
        return {"status": "timedOut", "version": None, "build": None}
    except OSError:
        return {"status": "failed", "version": None, "build": None}

    version = version_result.stdout.strip()
    build = build_result.stdout.strip()
    if (
        version_result.returncode != 0
        or build_result.returncode != 0
        or MACOS_VERSION_RE.fullmatch(version) is None
        or BUILD_RE.fullmatch(build) is None
    ):
        return {"status": "failed", "version": None, "build": None}
    return {"status": "passed", "version": version, "build": build}


def _default_resolver(executable: str) -> str | None:
    fixed = {
        "git": "/usr/bin/git",
        "sw_vers": "/usr/bin/sw_vers",
        "xcodebuild": "/usr/bin/xcodebuild",
        "swift": "/usr/bin/swift",
        "xcrun": "/usr/bin/xcrun",
    }
    candidate = fixed.get(executable)
    if candidate is not None:
        return candidate if Path(candidate).is_file() else None
    return shutil.which(executable)


def capture_environment(
    *,
    runner: Runner = _run,
    resolver: Resolver = _default_resolver,
    now: Callable[[], datetime] | None = None,
) -> dict[str, object]:
    repo_root = Path(__file__).resolve().parent.parent
    timestamp = (now or (lambda: datetime.now(timezone.utc)))()
    if timestamp.tzinfo is None:
        raise ValueError("capture timestamp must include a timezone")

    commands = {
        "xcodebuildVersion": _probe(
            "xcodebuild", ["-version"], XCODE_LINE_RE, repo_root, runner, resolver
        ),
        "swiftVersion": _probe(
            "swift", ["--version"], SWIFT_LINE_RE, repo_root, runner, resolver
        ),
        "cocoaPodsVersion": _probe(
            "pod", ["--version"], POD_VERSION_RE, repo_root, runner, resolver
        ),
        "macOSSDKVersion": _probe(
            "xcrun", ["--sdk", "macosx", "--show-sdk-version"], SDK_VERSION_RE,
            repo_root, runner, resolver,
        ),
        "macOSSDKBuildVersion": _probe(
            "xcrun", ["--sdk", "macosx", "--show-sdk-build-version"], BUILD_RE,
            repo_root, runner, resolver,
        ),
        "iOSSimulatorSDKVersion": _probe(
            "xcrun", ["--sdk", "iphonesimulator", "--show-sdk-version"], SDK_VERSION_RE,
            repo_root, runner, resolver,
        ),
        "iOSSimulatorSDKBuildVersion": _probe(
            "xcrun", ["--sdk", "iphonesimulator", "--show-sdk-build-version"], BUILD_RE,
            repo_root, runner, resolver,
        ),
    }
    repository = _repository(repo_root, runner, resolver)
    macos = _macos(repo_root, runner, resolver)
    complete = (
        repository["status"] == "passed"
        and repository["trackedChanges"] is False
        and macos["status"] == "passed"
        and all(probe["status"] == "passed" for probe in commands.values())
    )
    machine = platform.machine()
    if MACHINE_RE.fullmatch(machine) is None:
        machine = "unknown"

    return {
        "schemaVersion": SCHEMA_VERSION,
        "capturedAt": timestamp.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        "metadataOnly": True,
        "captureStatus": "complete" if complete else "incomplete",
        "repository": repository,
        "system": {
            "macOS": macos,
            "machine": machine,
        },
        "commands": commands,
    }


def main() -> int:
    document = capture_environment()
    json.dump(document, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0 if document["captureStatus"] == "complete" else 1


if __name__ == "__main__":
    raise SystemExit(main())
