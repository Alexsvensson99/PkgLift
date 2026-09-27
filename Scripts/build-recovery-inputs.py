#!/usr/bin/env python3
"""Build the exact local inputs consumed by ``run-recovery-drill.py``.

The output directory is intentionally new and task-owned. Its receipt is useful
only when this invocation built both artifacts and binds the unchanged source
inputs, commands, and local logs to their digests.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent.parent


def load_recovery():
    spec = importlib.util.spec_from_file_location("recovery_drill", ROOT / "Scripts/run-recovery-drill.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


recovery = load_recovery()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def normalized_new_directory(value, label):
    require(value.is_absolute(), label + " must be absolute")
    parent = value.parent.resolve(strict=True)
    require(parent.is_dir() and not parent.is_symlink(), label + " parent must be a real existing directory")
    result = parent / value.name
    require(not os.path.lexists(result), label + " must not exist")
    require(result != ROOT and ROOT not in result.parents, label + " must be outside the source checkout")
    return result


def normalized_existing_directory(value, label):
    require(value.is_absolute(), label + " must be absolute")
    try:
        result = value.resolve(strict=True)
    except FileNotFoundError as error:
        raise RuntimeError(label + " must be an existing directory") from error
    require(result.is_dir(), label + " must be an existing directory")
    require(result != ROOT and ROOT not in result.parents, label + " must be outside the source checkout")
    return result


def overlaps(left, right):
    return left == right or left.is_relative_to(right) or right.is_relative_to(left)


def validate_paths(args):
    output = normalized_new_directory(args.output, "Output")
    scratch = normalized_existing_directory(args.scratch_path, "Scratch path")
    cache = normalized_existing_directory(args.cache_path, "Cache path")
    require(not overlaps(scratch, cache) and not overlaps(scratch, output) and not overlaps(cache, output),
            "Scratch, cache, and output paths must not overlap")
    return output, scratch, cache


def log_metadata(path):
    return {"sha256": digest(path), "bytes": path.stat().st_size}


def execute(label, command, environment, logs):
    started = time.monotonic()
    stdout = logs / (label + ".stdout.log")
    stderr = logs / (label + ".stderr.log")
    with stdout.open("wb") as out, stderr.open("wb") as err:
        process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=out, stderr=err, start_new_session=True)
        try:
            code = process.wait(timeout=1200)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise
    return {
        "label": label,
        "arguments": command,
        "exitCode": code,
        "seconds": round(time.monotonic() - started, 2),
        "stdout": log_metadata(stdout),
        "stderr": log_metadata(stderr),
    }


def write_receipt(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-path", type=Path, required=True)
    parser.add_argument("--cache-path", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, choices=range(1, 5), default=2)
    args = parser.parse_args(argv)
    output, scratch, cache = validate_paths(args)
    before = recovery.source_inputs()
    output.mkdir()
    logs = output / "logs"
    temporary = output / "tmp"
    clang_cache = output / "clang-module-cache"
    swiftpm_module_cache = output / "swiftpm-module-cache"
    for directory in (logs, temporary, clang_cache, swiftpm_module_cache):
        directory.mkdir(parents=True, exist_ok=False)
    environment = dict(os.environ, TMPDIR=str(temporary), CLANG_MODULE_CACHE_PATH=str(clang_cache),
                       SWIFTPM_MODULECACHE_OVERRIDE=str(swiftpm_module_cache), SWIFT_MODULE_CACHE_PATH=str(swiftpm_module_cache),
                       SWIFT_MODULECACHE_PATH=str(swiftpm_module_cache))
    base = ["swift", "build", "--scratch-path", str(scratch), "--cache-path", str(cache), "--manifest-cache", "local",
            "--disable-automatic-resolution", "--jobs", str(args.jobs)]
    receipt = {"schemaVersion": 1, "status": "failed", "exitCode": None, "buildsBothArtifacts": False,
               "sourceInputs": before, "sourceInputsAfter": None, "commands": []}
    receipt_path = output / "build-receipt.json"
    try:
        build = execute("build-tests", [*base, "--build-tests"], environment, logs)
        receipt["commands"].append(build)
        receipt["exitCode"] = build["exitCode"]
        require(build["exitCode"] == 0, "Swift build --build-tests failed")
        bin_path = execute("show-bin-path", [*base, "--show-bin-path"], environment, logs)
        receipt["commands"].append(bin_path)
        receipt["exitCode"] = bin_path["exitCode"]
        require(bin_path["exitCode"] == 0, "Swift build --show-bin-path failed")
        product = Path((logs / "show-bin-path.stdout.log").read_text().strip()).resolve(strict=True)
        require(product.is_relative_to(scratch), "Swift product directory escaped the declared scratch path")
        binary = product / "pkglift"
        bundle = product / "PkgLiftCLITests.xctest"
        require(binary.is_file() and bundle.is_dir(), "Expected pkglift and PkgLiftCLITests.xctest are missing")
        after = recovery.source_inputs()
        require(after == before, "Build changed recovery source inputs")
        receipt.update(status="passed", exitCode=0, buildsBothArtifacts=True, sourceInputs=after,
                       sourceInputsAfter=after, binarySHA256=digest(binary), signalTestBundleSHA256=recovery.state_hash(recovery.snapshot(bundle)),
                       binary=str(binary), signalTestBundle=str(bundle))
    except (RuntimeError, subprocess.TimeoutExpired, OSError) as error:
        receipt["failure"] = str(error)
    finally:
        receipt["sourceInputsAfter"] = recovery.source_inputs()
        write_receipt(receipt_path, receipt)
    require(receipt["status"] == "passed", receipt.get("failure", "Recovery inputs did not complete"))
    print(receipt_path)


if __name__ == "__main__":
    main()
