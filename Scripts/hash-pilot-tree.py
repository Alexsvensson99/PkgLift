#!/usr/bin/env python3
"""Hash a pilot tree deterministically without following symlinks."""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
from pathlib import Path, PurePosixPath


def normalized_relative_path(value: str) -> str:
    candidate = PurePosixPath(value)
    if candidate.is_absolute() or not candidate.parts or ".." in candidate.parts:
        raise argparse.ArgumentTypeError("paths must be relative and contained")
    return candidate.as_posix().removeprefix("./")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("root")
    parser.add_argument(
        "--include",
        action="append",
        default=[],
        type=normalized_relative_path,
        help="Hash only this exact relative path; may be repeated.",
    )
    parser.add_argument(
        "--exclude-prefix",
        action="append",
        default=[],
        type=normalized_relative_path,
        help="Exclude this relative path and its descendants; may be repeated.",
    )
    return parser.parse_args()


def is_excluded(relative: str, prefixes: set[str]) -> bool:
    return any(relative == prefix or relative.startswith(f"{prefix}/") for prefix in prefixes)


def tree_entries(root: Path, excluded: set[str]) -> list[tuple[str, Path]]:
    entries: list[tuple[str, Path]] = []
    for directory, directories, files in os.walk(root, followlinks=False):
        directory_path = Path(directory)

        retained_directories: list[str] = []
        for name in sorted(directories):
            path = directory_path / name
            relative = path.relative_to(root).as_posix()
            if is_excluded(relative, excluded):
                continue
            if path.is_symlink():
                entries.append((relative, path))
            else:
                retained_directories.append(name)
        directories[:] = retained_directories

        for name in sorted(files):
            path = directory_path / name
            relative = path.relative_to(root).as_posix()
            if not is_excluded(relative, excluded):
                entries.append((relative, path))
    return sorted(entries, key=lambda item: item[0])


def hash_entry(digest: hashlib._Hash, relative: str, path: Path) -> None:
    digest.update(relative.encode("utf-8"))
    digest.update(b"\0")
    if path.is_symlink():
        digest.update(b"symlink\0")
        digest.update(os.readlink(path).encode("utf-8"))
    elif path.is_file():
        digest.update(b"file\0")
        with path.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                digest.update(chunk)
    else:
        raise ValueError(f"Unsupported pilot tree entry: {relative}")
    digest.update(b"\0")


def main() -> None:
    args = parse_args()
    root = Path(args.root).resolve()
    if not root.is_dir():
        raise SystemExit(f"Pilot root is not a directory: {root}")

    excluded = set(args.exclude_prefix)
    entries = tree_entries(root, excluded)
    if args.include:
        requested = set(args.include)
        entries = [entry for entry in entries if entry[0] in requested]
        missing = requested.difference(relative for relative, _ in entries)
        if missing:
            raise SystemExit(f"Missing included pilot path(s): {', '.join(sorted(missing))}")

    digest = hashlib.sha256()
    for relative, path in entries:
        hash_entry(digest, relative, path)
    print(digest.hexdigest())


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error
