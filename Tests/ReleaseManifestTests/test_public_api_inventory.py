"""Compiler-backed public API inventory boundaries."""

import hashlib
import json
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/capture-public-api.py"
MODULES = (
    "PkgLiftCore", "PkgLiftCocoaPods", "PkgLiftXcode",
    "PkgLiftRegistry", "PkgLiftMigration", "PkgLiftVerification",
)


class PublicAPIInventoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.products = self.root / "products"
        self.cache = self.root / "cache"
        self.sdk = self.root / "MacOSX.test.sdk"
        for path in (self.products, self.cache, self.sdk):
            path.mkdir()
        source_inputs = {}
        for module in MODULES:
            source = self.root / "Sources" / module / "API.swift"
            source.parent.mkdir(parents=True)
            source.write_text(f"public struct {module}API {{}}\n")
            source_inputs[source.relative_to(self.root).as_posix()] = hashlib.sha256(source.read_bytes()).hexdigest()
            if module == "PkgLiftCore":
                version = source.parent / "Version.swift"
                version.write_text('public let pkgLiftVersion = "1.0.0"\n')
                source_inputs[version.relative_to(self.root).as_posix()] = hashlib.sha256(
                    version.read_bytes()).hexdigest()
            container = self.products / f"{module}.swiftmodule"
            container.mkdir()
            (container / "arm64-apple-macos.swiftmodule").write_bytes((module + " module").encode())
        resource = self.root / "Sources/PkgLiftRegistry/BundledRegistry/example.yml"
        resource.parent.mkdir(parents=True)
        resource.write_text("schemaVersion: 2\n")
        source_inputs[resource.relative_to(self.root).as_posix()] = hashlib.sha256(resource.read_bytes()).hexdigest()
        self.receipt = self.root / "receipt.json"
        self.write_receipt(source_inputs)
        self.extractor = self.root / "fake-symbolgraph-extract.py"
        self.extractor.write_text("""#!/usr/bin/env python3
import json, pathlib, sys
if '-version' in sys.argv:
    print('Apple Swift version test')
    raise SystemExit(0)
module = sys.argv[sys.argv.index('-module-name') + 1]
products = pathlib.Path(sys.argv[sys.argv.index('-I') + 1])
output = pathlib.Path(sys.argv[sys.argv.index('-output-dir') + 1])
suffix = ' changed' if (products / 'BREAK').exists() else ''
line = 99 if (products / 'DOC_LINE_DRIFT').exists() else 1
parent = 's:' + module + '.Container'
member = 's:' + module + '.Container.member'
graph = {
  'metadata': {'formatVersion': {'major': 0, 'minor': 6, 'patch': 0}},
  'module': {'name': module, 'platform': {'architecture': 'arm64'}},
  'symbols': [
    {'identifier': {'precise': parent}, 'names': {'title': 'Container'},
     'docComment': {'uri': 'file:///private/source.swift', 'lines': [
       {'text': 'API.', 'range': {'start': {'line': line, 'character': 0},
                                  'end': {'line': line, 'character': 4}}}]},
     'location': {'uri': 'file:///private/source.swift', 'position': {'line': 1}}},
    {'identifier': {'precise': member}, 'names': {'title': 'member'},
     'declarationFragments': [{'kind': 'keyword', 'spelling': 'func'},
                              {'kind': 'text', 'spelling': ' member()' + suffix}]}
  ],
  'relationships': [{'kind': 'memberOf', 'source': member, 'target': parent}]
}
(output / (module + '.symbols.json')).write_text(json.dumps(graph))
""")
        self.extractor.chmod(self.extractor.stat().st_mode | stat.S_IXUSR)
        swiftc = self.root / "swiftc"
        swiftc.write_text("#!/bin/sh\necho 'Apple Swift version test'\necho 'Target: arm64-apple-macosx14.0'\n")
        swiftc.chmod(swiftc.stat().st_mode | stat.S_IXUSR)

    def module_artifacts(self, products=None):
        products = products or self.products
        result = {}
        for module in MODULES:
            artifact = products / f"{module}.swiftmodule/arm64-apple-macos.swiftmodule"
            result[module] = {
                "path": str(artifact.resolve()),
                "bytes": artifact.stat().st_size,
                "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
            }
        return result

    def write_receipt(self, inputs, artifacts=None):
        self.receipt.write_text(json.dumps({
            "status": "passed",
            "exitCode": 0,
            "buildsBothArtifacts": True,
            "commands": [{"label": "build-tests", "exitCode": 0}],
            "sourceInputs": inputs,
            "sourceInputsAfter": inputs,
            "publicModuleArtifacts": artifacts or self.module_artifacts(),
        }))

    def command(self, *extra):
        return ["python3", str(SCRIPT), "--source-root", str(self.root),
                "--products-dir", str(self.products), "--build-receipt", str(self.receipt),
                "--symbolgraph-extract", str(self.extractor), "--sdk", str(self.sdk),
                "--module-cache-path", str(self.cache), *map(str, extra)]

    def run_capture(self, *extra):
        return subprocess.run(self.command(*extra), capture_output=True, text=True, check=False)

    def test_capture_preserves_nested_member_relation_and_removes_local_location(self):
        output = self.root / "public-api.json"
        result = self.run_capture("--output", output)
        self.assertEqual(0, result.returncode, result.stderr)
        document = json.loads(output.read_text())
        self.assertEqual(list(MODULES), document["scope"]["libraryTargets"])
        self.assertEqual("1.0.0", document["packageVersion"])
        core_graph = document["modules"][0]["symbolGraphs"][0]["graph"]
        self.assertEqual("memberOf", core_graph["relationships"][0]["kind"])
        self.assertEqual("s:PkgLiftCore.Container.member", core_graph["relationships"][0]["source"])
        self.assertNotIn("location", json.dumps(core_graph))
        self.assertNotIn("file://", json.dumps(core_graph))
        parent = next(symbol for symbol in core_graph["symbols"] if "docComment" in symbol)
        self.assertEqual({"text": "API."}, parent["docComment"]["lines"][0])
        self.assertEqual(2, document["modules"][0]["symbolCount"])

    def test_check_ignores_internal_source_drift_but_rejects_public_graph_drift(self):
        baseline = self.root / "baseline.json"
        self.assertEqual(0, self.run_capture("--output", baseline).returncode)
        source = self.root / "Sources/PkgLiftMigration/API.swift"
        source.write_text(source.read_text() + "private let implementationDetail = 1\n")
        receipt = json.loads(self.receipt.read_text())
        relative = source.relative_to(self.root).as_posix()
        receipt["sourceInputs"][relative] = hashlib.sha256(source.read_bytes()).hexdigest()
        self.write_receipt(receipt["sourceInputs"])
        same_api = self.run_capture("--check", baseline)
        self.assertEqual(0, same_api.returncode, same_api.stderr)
        self.assertIn("Source bytes changed", same_api.stdout)
        (self.products / "DOC_LINE_DRIFT").touch()
        line_drift = self.run_capture("--check", baseline)
        self.assertEqual(0, line_drift.returncode, line_drift.stderr)
        (self.products / "BREAK").touch()
        changed_api = self.run_capture("--check", baseline)
        self.assertEqual(1, changed_api.returncode)
        self.assertIn("Public API changed in:", changed_api.stderr)

    def test_missing_module_and_stale_build_receipt_fail_before_baseline_creation(self):
        output = self.root / "missing.json"
        (self.products / "PkgLiftRegistry.swiftmodule/arm64-apple-macos.swiftmodule").unlink()
        missing = self.run_capture("--output", output)
        self.assertEqual(1, missing.returncode)
        self.assertIn("Built Swift module", missing.stderr)
        self.assertFalse(output.exists())
        (self.products / "PkgLiftRegistry.swiftmodule/arm64-apple-macos.swiftmodule").write_bytes(b"module")
        source = self.root / "Sources/PkgLiftRegistry/API.swift"
        source.write_text(source.read_text() + "public let newAPI = true\n")
        stale = self.run_capture("--output", output)
        self.assertEqual(1, stale.returncode)
        self.assertIn("differs from the completed build receipt", stale.stderr)
        self.assertFalse(output.exists())

    def test_receipt_rejects_failed_build_different_module_bytes_and_different_product_path(self):
        output = self.root / "invalid-provenance.json"
        receipt = json.loads(self.receipt.read_text())
        receipt["status"] = "failed"
        self.receipt.write_text(json.dumps(receipt))
        failed = self.run_capture("--output", output)
        self.assertEqual(1, failed.returncode)
        self.assertIn("does not prove a successful build", failed.stderr)

        inputs = receipt["sourceInputs"]
        receipt["status"] = "passed"
        receipt["sourceInputsAfter"] = {}
        self.receipt.write_text(json.dumps(receipt))
        changed_sources = self.run_capture("--output", output)
        self.assertEqual(1, changed_sources.returncode)
        self.assertIn("unchanged source inputs", changed_sources.stderr)

        receipt["sourceInputsAfter"] = inputs
        receipt.pop("publicModuleArtifacts")
        self.receipt.write_text(json.dumps(receipt))
        missing_bindings = self.run_capture("--output", output)
        self.assertEqual(1, missing_bindings.returncode)
        self.assertIn("no publicModuleArtifacts", missing_bindings.stderr)

        self.write_receipt(inputs)
        artifact = self.products / "PkgLiftMigration.swiftmodule/arm64-apple-macos.swiftmodule"
        artifact.write_bytes(b"different module bytes")
        changed = self.run_capture("--output", output)
        self.assertEqual(1, changed.returncode)
        self.assertIn("module bytes do not match", changed.stderr)
        self.assertFalse(output.exists())

        artifact.write_bytes(b"PkgLiftMigration module")
        self.write_receipt(inputs)
        copied_products = self.root / "copied-products"
        shutil.copytree(self.products, copied_products)
        original_products = self.products
        self.products = copied_products
        self.addCleanup(setattr, self, "products", original_products)
        copied = self.run_capture("--output", output)
        self.assertEqual(1, copied.returncode)
        self.assertIn("module path does not match", copied.stderr)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
