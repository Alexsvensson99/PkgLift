"""Offline checks of the CocoaPods script acceptance boundary; no pod install."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'Scripts/validate-real-project-cocoapods.rb'


def ruby(code, *args):
    return subprocess.run(['ruby', '-r', str(HELPER), '-e', code, *map(str, args)],
                          capture_output=True, text=True, check=False)


class CocoaPodsGuardTests(unittest.TestCase):
    def test_exact_script_comparison_accepts_known_bytes_and_rejects_append(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'generated.sh'
            expected = '#!/bin/sh\n# https://reviewed.example/template\nrsync --delete source destination\n'
            path.write_text(expected)
            code = 'G3CocoaPods.compare_script(Pathname(ARGV[0]), ARGV[1])'
            self.assertEqual(ruby(code, path, expected).returncode, 0)
            path.write_text(expected + 'unreviewed_command\n')
            self.assertNotEqual(ruby(code, path, expected).returncode, 0)

    def test_shell_body_owner_and_extra_phase_are_bound(self):
        code = """
body = G3CocoaPods::COPY_BODY
phase = {'isa'=>'PBXShellScriptBuildPhase','name'=>'[CP] Copy XCFrameworks',
         'shellPath'=>'/bin/sh','shellScript'=>body}
target = {'isa'=>'PBXAggregateTarget','name'=>'AmazonIVSPlayer','buildPhases'=>['phase']}
document = {'objects'=>{'phase'=>phase,'target'=>target}}
case ARGV[0]
when 'append'; phase['shellScript'] += "echo unreviewed\\n"
when 'owner'; target['name'] = 'Unreviewed target'
when 'extra'; document['objects']['extra'] = phase.dup
end
G3CocoaPods.validate_shells(document, '[CP] Copy XCFrameworks'=>body)
"""
        self.assertEqual(ruby(code, 'valid').returncode, 0)
        for fault in ['append', 'owner', 'extra']:
            with self.subTest(fault=fault):
                self.assertNotEqual(ruby(code, fault).returncode, 0)

    def test_xcframework_metadata_cannot_inject_generated_shell(self):
        base = {'LibraryIdentifier': 'ios-arm64_x86_64-simulator',
                'LibraryPath': 'AmazonIVSPlayer.framework', 'SupportedPlatform': 'ios',
                'SupportedPlatformVariant': 'simulator', 'SupportedArchitectures': ['arm64', 'x86_64']}
        code = 'G3CocoaPods.validate_libraries(JSON.parse(ARGV[0]))'
        self.assertEqual(ruby(code, json.dumps({'AvailableLibraries': [base]})).returncode, 0)
        for key, value in [('LibraryIdentifier', 'bad";command;"'), ('LibraryPath', '../outside.framework'),
                           ('SupportedPlatformVariant', '$(command)'), ('SupportedArchitectures', ['arm64;command'])]:
            with self.subTest(key=key):
                changed = dict(base, **{key: value})
                self.assertNotEqual(ruby(code, json.dumps({'AvailableLibraries': [changed]})).returncode, 0)
        self.assertNotEqual(ruby(code, json.dumps({'AvailableLibraries': [base, base]})).returncode, 0)

    def test_generated_input_cannot_escape_through_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            selected = root / 'selected'
            selected.mkdir()
            outside = root / 'outside'
            outside.write_text('not reviewed')
            (selected / 'input').symlink_to(outside)
            result = ruby('G3CocoaPods.regular_file(Pathname(ARGV[0]), "input")', selected)
            self.assertNotEqual(result.returncode, 0)

    def test_file_lists_are_required_and_direct_paths_rejected(self):
        code = '''
stem = 'AmazonIVSPlayer/AmazonIVSPlayer-xcframeworks'
prefix = '${PODS_ROOT}/Target Support Files/' + stem
phase = {'inputFileListPaths'=>[prefix + '-input-files.xcfilelist'],
         'outputFileListPaths'=>[prefix + '-output-files.xcfilelist']}
case ARGV[0]
when 'missing'; phase.delete('inputFileListPaths')
when 'replaced'; phase['outputFileListPaths'] = ['unreviewed']
when 'direct'; phase['inputPaths'] = ['unreviewed']
end
G3CocoaPods.validate_phase_lists(phase, stem)
'''
        self.assertEqual(ruby(code, 'valid').returncode, 0)
        for fault in ['missing', 'replaced', 'direct']:
            self.assertNotEqual(ruby(code, fault).returncode, 0)


if __name__ == '__main__':
    unittest.main()
