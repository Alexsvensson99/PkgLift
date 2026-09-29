#!/usr/bin/env python3
"""Capture or compare the compiler-emitted public API of PkgLift libraries."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Sequence

sys.dont_write_bytecode = True

FORMAT = "pkglift-public-api-inventory/v1"
MODULES = (
    "PkgLiftCore",
    "PkgLiftCocoaPods",
    "PkgLiftXcode",
    "PkgLiftRegistry",
    "PkgLiftMigration",
    "PkgLiftVerification",
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
VERSION_RE = re.compile(r'^public let pkgLiftVersion = "([0-9]+\.[0-9]+\.[0-9]+)"$', re.MULTILINE)


class InventoryError(RuntimeError):
    """Raised when an inventory cannot be captured without assumptions."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise InventoryError(message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def regular_file(path: Path, label: str) -> None:
    require(path.is_file() and not path.is_symlink(), f"{label} must be a regular file: {path}")


def load_json(path: Path, label: str) -> dict[str, Any]:
    regular_file(path, label)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise InventoryError(f"{label} is not valid UTF-8 JSON: {path}") from error
    require(isinstance(value, dict), f"{label} must contain a JSON object: {path}")
    return value


def source_inventory(source_root: Path, receipt: dict[str, Any]) -> tuple[list[dict[str, Any]], str, str]:
    source_root = source_root.resolve()
    require(source_root.is_dir(), f"Source root does not exist: {source_root}")
    inputs = receipt.get("sourceInputs")
    require(isinstance(inputs, dict), "Build receipt has no sourceInputs object.")
    records: list[dict[str, Any]] = []
    for module in MODULES:
        directory = source_root / "Sources" / module
        require(directory.is_dir() and not directory.is_symlink(), f"Missing source directory: Sources/{module}")
        files = sorted(directory.rglob("*.swift"))
        require(files, f"Public module has no Swift sources: {module}")
        for path in files:
            regular_file(path, "Public module source")
            relative = path.relative_to(source_root).as_posix()
            data = path.read_bytes()
            digest = sha256_bytes(data)
            receipt_digest = inputs.get(relative)
            require(isinstance(receipt_digest, str) and SHA256_RE.fullmatch(receipt_digest) is not None,
                    f"Build receipt does not bind public source: {relative}")
            require(digest == receipt_digest, f"Public source differs from the completed build receipt: {relative}")
            records.append({"path": relative, "bytes": len(data), "sha256": digest})
    expected = {record["path"] for record in records}
    receipt_public = {
        name for name in inputs
        if name.endswith(".swift") and any(name.startswith(f"Sources/{module}/") for module in MODULES)
    }
    require(receipt_public == expected, "Build receipt public-source set differs from the six library targets.")
    encoded = json.dumps(records, sort_keys=True, separators=(",", ":")).encode()
    version_path = source_root / "Sources/PkgLiftCore/Version.swift"
    match = VERSION_RE.search(version_path.read_text(encoding="utf-8"))
    require(match is not None, "PkgLift public version constant is missing or malformed.")
    return records, sha256_bytes(encoded), match.group(1)


def compiler_version(executable: Path, source_root: Path) -> list[str]:
    swiftc = executable.parent / "swiftc"
    require(swiftc.is_file() and os.access(swiftc, os.X_OK),
            f"swiftc is not executable beside swift-symbolgraph-extract: {swiftc}")
    result = run([str(swiftc), "--version"], source_root, timeout=15)
    require(result.returncode == 0, "swiftc --version failed.")
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    require(1 <= len(lines) <= 4 and all(len(line) <= 240 for line in lines),
            "swiftc returned an unsupported version string.")
    return lines


def run(command: Sequence[str], cwd: Path, timeout: int, environment: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update({"LC_ALL": "C", "LANG": "C"})
    if environment:
        env.update(environment)
    try:
        return subprocess.run(list(command), cwd=cwd, env=env, capture_output=True, text=True,
                              timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        raise InventoryError(f"Compiler API extraction timed out after {timeout} seconds.") from error
    except OSError as error:
        raise InventoryError("Could not execute swift-symbolgraph-extract.") from error


def normalize_graph(value: Any) -> Any:
    if isinstance(value, dict):
        normalized = {
            key: normalize_graph(item)
            for key, item in value.items()
            if key not in {"location", "uri"}
        }
        if isinstance(normalized.get("symbols"), list):
            normalized["symbols"] = sorted(normalized["symbols"], key=lambda item: json.dumps(item, sort_keys=True))
        if isinstance(normalized.get("relationships"), list):
            normalized["relationships"] = sorted(
                normalized["relationships"], key=lambda item: json.dumps(item, sort_keys=True))
        doc_comment = normalized.get("docComment")
        if isinstance(doc_comment, dict) and isinstance(doc_comment.get("lines"), list):
            for line in doc_comment["lines"]:
                if isinstance(line, dict):
                    line.pop("range", None)
        return {key: normalized[key] for key in sorted(normalized)}
    if isinstance(value, list):
        return [normalize_graph(item) for item in value]
    return value


def module_artifact(products_dir: Path, module: str, architecture: str) -> Path:
    container = products_dir / f"{module}.swiftmodule"
    require(container.is_dir() and not container.is_symlink(), f"Built module directory is missing: {container}")
    artifact = container / f"{architecture}-apple-macos.swiftmodule"
    regular_file(artifact, "Built Swift module")
    return artifact


def validated_module_artifacts(products_dir: Path, architecture: str,
                               receipt: dict[str, Any]) -> dict[str, tuple[Path, str]]:
    bindings = receipt.get("publicModuleArtifacts")
    require(isinstance(bindings, dict), "Build receipt has no publicModuleArtifacts object.")
    require(set(bindings) == set(MODULES),
            "Build receipt does not bind exactly the six public module artifacts.")
    artifacts: dict[str, tuple[Path, str]] = {}
    for module in MODULES:
        record = bindings[module]
        require(isinstance(record, dict), f"Build receipt has an invalid module record: {module}")
        path_value, size, digest = record.get("path"), record.get("bytes"), record.get("sha256")
        require(isinstance(path_value, str) and Path(path_value).is_absolute(),
                f"Build receipt has no absolute module path for {module}.")
        require(isinstance(size, int) and size >= 0,
                f"Build receipt has an invalid module size for {module}.")
        require(isinstance(digest, str) and SHA256_RE.fullmatch(digest) is not None,
                f"Build receipt has an invalid module digest for {module}.")
        artifact = module_artifact(products_dir, module, architecture)
        try:
            receipt_path = Path(path_value).resolve(strict=True)
        except OSError as error:
            raise InventoryError(f"Build receipt module path is unavailable for {module}.") from error
        require(receipt_path == artifact.resolve(),
                f"Built module path does not match the build receipt: {module}")
        require(artifact.stat().st_size == size and sha256_file(artifact) == digest,
                f"Built module bytes do not match the build receipt: {module}")
        artifacts[module] = (artifact, digest)
    return artifacts


def extract_module(*, module: str, artifact: Path, expected_artifact_digest: str,
                   products_dir: Path, source_root: Path, sdk: Path,
                   target: str, module_cache: Path, extractor: Path,
                   include_paths: list[Path]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix=f"{module}-", dir=module_cache) as temporary:
        output_dir = Path(temporary) / "symbolgraphs"
        output_dir.mkdir()
        command = [
            str(extractor), "-module-name", module, "-I", str(products_dir),
        ]
        for include_path in include_paths:
            command.extend(["-I", str(include_path)])
        command.extend([
            "-target", target, "-sdk", str(sdk), "-swift-version", "6",
            "-minimum-access-level", "public", "-module-cache-path", str(module_cache),
            "-output-dir", str(output_dir),
        ])
        result = run(command, source_root, timeout=90,
                     environment={"CLANG_MODULE_CACHE_PATH": str(module_cache)})
        if result.returncode != 0:
            detail = next((line.strip() for line in result.stderr.splitlines() if line.strip()), "unknown compiler error")
            raise InventoryError(f"Public API extraction failed for {module}: {detail[:300]}")
        graph_paths = sorted(output_dir.glob("*.symbols.json"))
        require(graph_paths, f"Compiler emitted no symbol graph for {module}.")
        graphs: list[dict[str, Any]] = []
        symbol_count = 0
        for path in graph_paths:
            graph = normalize_graph(load_json(path, "Compiler symbol graph"))
            symbols = graph.get("symbols")
            require(isinstance(symbols, list), f"Compiler symbol graph has no symbols array: {path.name}")
            symbol_count += len(symbols)
            graphs.append({"file": path.name, "graph": graph})
        require(symbol_count > 0, f"Compiler emitted an empty public API for {module}.")
    artifact_digest = sha256_file(artifact)
    require(artifact_digest == expected_artifact_digest,
            f"Built module changed during public API extraction: {module}")
    surface_bytes = json.dumps(graphs, sort_keys=True, separators=(",", ":")).encode()
    return {
        "name": module,
        "moduleArtifact": {"bytes": artifact.stat().st_size, "sha256": artifact_digest},
        "symbolCount": symbol_count,
        "symbolGraphs": graphs,
        "apiSurfaceSHA256": sha256_bytes(surface_bytes),
    }


def capture(args: argparse.Namespace) -> dict[str, Any]:
    source_root = args.source_root.resolve()
    products_dir = args.products_dir.resolve()
    sdk_name = args.sdk.name
    sdk = args.sdk.resolve()
    module_cache = args.module_cache_path.resolve()
    receipt_path = args.build_receipt.resolve()
    # Preserve the executable basename: Apple's tool is a swift-frontend symlink,
    # and resolving it changes the driver's option mode.
    extractor = args.symbolgraph_extract.absolute()
    include_paths = [path.resolve() for path in args.include_path]
    require(products_dir.is_dir() and not products_dir.is_symlink(), "Products directory must be a real directory.")
    require(sdk.is_dir(), "SDK path must be an existing directory.")
    require(module_cache.is_dir() and not module_cache.is_symlink(), "Module cache path must be a real existing directory.")
    require(extractor.is_file() and os.access(extractor, os.X_OK), "Symbol graph extractor is not executable.")
    require(all(path.is_dir() for path in include_paths), "Every include path must be an existing directory.")
    receipt = load_json(receipt_path, "Build receipt")
    require(receipt.get("status") == "passed" and receipt.get("exitCode") == 0
            and receipt.get("buildsBothArtifacts") is True
            and receipt.get("sourceInputsAfter") == receipt.get("sourceInputs"),
            "Build receipt does not prove a successful build with unchanged source inputs.")
    commands = receipt.get("commands")
    require(isinstance(commands, list) and any(isinstance(item, dict) and item.get("label") == "build-tests"
            and item.get("exitCode") == 0 for item in commands), "Build receipt has no successful build-tests command.")
    sources, source_digest, version = source_inventory(source_root, receipt)
    architecture = args.target.split("-", 1)[0]
    artifacts = validated_module_artifacts(products_dir, architecture, receipt)
    modules = [extract_module(module=module, artifact=artifacts[module][0],
                              expected_artifact_digest=artifacts[module][1],
                              products_dir=products_dir, source_root=source_root, sdk=sdk,
                              target=args.target, module_cache=module_cache, extractor=extractor,
                              include_paths=include_paths)
               for module in MODULES]
    return {
        "schemaVersion": 1,
        "format": FORMAT,
        "packageVersion": version,
        "scope": {"accessLevel": "public", "libraryTargets": list(MODULES),
                  "locationsRemoved": True, "compilerGenerated": True},
        "compiler": {"swiftCompilerVersion": compiler_version(extractor, source_root),
                     "target": args.target, "sdk": sdk_name},
        "buildReceiptSHA256": sha256_file(receipt_path),
        "sourceTreeSHA256": source_digest,
        "sourceFiles": sources,
        "modules": modules,
    }


def api_surface(document: dict[str, Any]) -> dict[str, str]:
    require(document.get("format") == FORMAT, "API baseline uses an unsupported format.")
    modules = document.get("modules")
    require(isinstance(modules, list), "API baseline has no modules array.")
    values: dict[str, str] = {}
    for item in modules:
        require(isinstance(item, dict), "API baseline contains an invalid module record.")
        name, digest = item.get("name"), item.get("apiSurfaceSHA256")
        require(name in MODULES and isinstance(digest, str) and SHA256_RE.fullmatch(digest) is not None,
                "API baseline contains an invalid module identity or digest.")
        require(name not in values, f"API baseline repeats module: {name}")
        values[name] = digest
    require(set(values) == set(MODULES), "API baseline does not contain exactly the six public library targets.")
    return values


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parent.parent)
    result.add_argument("--products-dir", type=Path, required=True)
    result.add_argument("--build-receipt", type=Path, required=True)
    result.add_argument("--symbolgraph-extract", type=Path, required=True)
    result.add_argument("--sdk", type=Path, required=True)
    result.add_argument("--target", default="arm64-apple-macosx14.0")
    result.add_argument("--module-cache-path", type=Path, required=True)
    result.add_argument("--include-path", type=Path, action="append", default=[])
    mode = result.add_mutually_exclusive_group(required=True)
    mode.add_argument("--output", type=Path)
    mode.add_argument("--check", type=Path, metavar="BASELINE")
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        document = capture(args)
        if args.output is not None:
            output = args.output.absolute()
            require(not output.exists() and not output.is_symlink(), "Output path must be new.")
            require(output.parent.is_dir(), "Output parent directory does not exist.")
            output.write_text(
                json.dumps(document, sort_keys=True, separators=(",", ":")) + "\n",
                encoding="utf-8",
            )
            print(f"Captured public API for {len(MODULES)} modules at {output}")
            return 0
        baseline = load_json(args.check.absolute(), "API baseline")
        expected, actual = api_surface(baseline), api_surface(document)
        changed = [module for module in MODULES if expected[module] != actual[module]]
        if changed:
            raise InventoryError("Public API changed in: " + ", ".join(changed))
        print("Public API matches the six-module baseline.")
        if baseline.get("sourceTreeSHA256") != document.get("sourceTreeSHA256"):
            print("Source bytes changed without changing the compiler-emitted public API.")
        return 0
    except (InventoryError, OSError, ValueError) as error:
        print(f"public API capture failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
