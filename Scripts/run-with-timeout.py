#!/usr/bin/env python3
"""Run one command with a hard deadline and optional log capture.

This helper exists because GitHub's macOS images do not ship GNU `timeout`.
It starts the command in a separate process group so descendants such as
xcodebuild, git, and CocoaPods are terminated together on timeout.
"""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import IO, Sequence


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seconds", type=int, required=True)
    parser.add_argument("--cwd")
    output = parser.add_mutually_exclusive_group()
    output.add_argument("--combined-log")
    output.add_argument("--stdout")
    parser.add_argument("--stderr")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    if args.seconds <= 0:
        parser.error("--seconds must be greater than zero")
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")
    if args.combined_log and args.stderr:
        parser.error("--stderr cannot be combined with --combined-log")
    return args


def open_output(path: str | None) -> IO[bytes] | None:
    if path is None:
        return None
    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    return output_path.open("wb")


def terminate_group(process: subprocess.Popen[bytes]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return

    try:
        process.wait(timeout=10)
        return
    except subprocess.TimeoutExpired:
        pass

    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    process.wait()


def pump_combined(
    source: IO[bytes],
    log: IO[bytes],
) -> None:
    while True:
        chunk = source.read(64 * 1024)
        if not chunk:
            break
        log.write(chunk)
        log.flush()
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()


def run(args: argparse.Namespace) -> int:
    stdout_handle: IO[bytes] | int | None
    stderr_handle: IO[bytes] | int | None
    combined_handle: IO[bytes] | None = None
    pump_thread: threading.Thread | None = None

    try:
        if args.combined_log:
            combined_handle = open_output(args.combined_log)
            assert combined_handle is not None
            stdout_handle = subprocess.PIPE
            stderr_handle = subprocess.STDOUT
        else:
            stdout_handle = open_output(args.stdout) or None
            stderr_handle = open_output(args.stderr) or None

        process = subprocess.Popen(
            args.command,
            cwd=args.cwd,
            stdout=stdout_handle,
            stderr=stderr_handle,
            start_new_session=True,
        )

        if args.combined_log:
            assert process.stdout is not None
            assert combined_handle is not None
            pump_thread = threading.Thread(
                target=pump_combined,
                args=(process.stdout, combined_handle),
                daemon=True,
            )
            pump_thread.start()

        deadline = time.monotonic() + args.seconds
        while process.poll() is None:
            if time.monotonic() >= deadline:
                print(
                    f"Command timed out after {args.seconds} seconds: "
                    + " ".join(args.command),
                    file=sys.stderr,
                    flush=True,
                )
                terminate_group(process)
                if pump_thread is not None:
                    pump_thread.join(timeout=5)
                return 124
            time.sleep(0.25)

        if pump_thread is not None:
            pump_thread.join(timeout=5)
        return int(process.returncode or 0)
    finally:
        for handle in (stdout_handle if "stdout_handle" in locals() else None,
                       stderr_handle if "stderr_handle" in locals() else None,
                       combined_handle):
            if handle is not None and handle not in (subprocess.PIPE, subprocess.STDOUT):
                handle.close()


def main() -> None:
    sys.exit(run(parse_args()))


if __name__ == "__main__":
    main()
