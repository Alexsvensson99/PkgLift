#!/usr/bin/env python3
"""Report whether a GitHub Actions change set matches any supplied glob."""

from __future__ import annotations

import fnmatch
import os
import re
import subprocess
import sys


SHA = re.compile(r"[0-9a-f]{40}")


def valid_sha(value: str) -> bool:
    return bool(SHA.fullmatch(value)) and set(value) != {"0"}


def changed_paths(base: str, head: str) -> list[str]:
    result = subprocess.run(
        ["git", "diff", "--name-only", "--no-renames", base, head],
        check=True,
        text=True,
        capture_output=True,
    )
    return [path for path in result.stdout.splitlines() if path]


def main() -> None:
    patterns = sys.argv[1:]
    if not patterns:
        raise SystemExit("usage: ci-paths-relevant.py GLOB [GLOB ...]")

    event = os.environ.get("GITHUB_EVENT_NAME", "")
    if event in {"schedule", "workflow_dispatch"}:
        print("true")
        return

    base = os.environ.get("PKGLIFT_BASE_SHA", "")
    head = os.environ.get("PKGLIFT_HEAD_SHA", "")
    if not valid_sha(base) or not valid_sha(head):
        # A new branch push has an all-zero before SHA. Run the heavy check
        # instead of allowing incomplete event metadata to skip validation.
        print("true")
        return

    paths = changed_paths(base, head)
    relevant = any(
        fnmatch.fnmatchcase(path, pattern)
        for path in paths
        for pattern in patterns
    )
    print("true" if relevant else "false")


if __name__ == "__main__":
    main()
