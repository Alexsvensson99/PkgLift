"""Offline safety regressions for real-project refusal controls."""
import copy
import importlib.util
import json
import os
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('real_refusal', ROOT / 'Scripts/run-real-project-refusal.py')
pilot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pilot)


class RefusalTests(unittest.TestCase):
    def setUp(self):
        self.case = next(c for c in json.loads(pilot.INTAKE.read_text())['cases'] if c['id'] == 'firebaseui-project')
        self.source = Path('/disposable/source')
        names = ['FirebaseUI', 'FirebaseDatabaseUI', 'FirebaseFirestoreUI', 'FirebaseStorageUI', 'Firebase/Auth']
        self.analysis = {'project': {'projectPath': str(self.source / self.case['root'] / self.case['project'])},
                         'candidates': [{'pod': {'name': n, 'isDirect': True},
                                         'classification': 'REVIEW' if n == 'Firebase/Auth' else 'BLOCKED'} for n in names]}
        self.plan = {'projectPath': self.analysis['project']['projectPath'],
                     'entries': [{'podName': c['pod']['name'], 'classification': c['classification'],
                                  'actions': [{'manual': {'description': 'review'}}]} for c in self.analysis['candidates']]}

    def check(self):
        pilot.check_selection(self.analysis, self.plan, self.case, self.source)

    def test_safety_validator_failure_is_not_reported_as_input_failure(self):
        summary = {'status': 'blocked-input'}
        pilot.record_failure(summary, pilot.CommandFailure('validate-refusal', 'failed-safety'), [])
        self.assertEqual(summary['status'], 'failed-safety')
        self.assertEqual(summary['error'], 'Command failed: validate-refusal')
        pilot.record_failure(summary, pilot.CommandFailure('fetch', 'blocked-input'), [])
        self.assertEqual(summary['status'], 'blocked-input')
        # Error text cannot impersonate a typed input failure.
        pilot.record_failure(summary, RuntimeError('Command failed: /private/source'), [Path('/private/source')])
        self.assertEqual(summary['status'], 'failed-safety')
        self.assertNotIn('/private/source', summary['error'])

    def test_plan_exclusion_works_without_git_templates_in_both_runners(self):
        aws_spec = importlib.util.spec_from_file_location('g3_aws_exclusion', ROOT / 'Scripts/run-real-project-aws.py')
        aws_runner = importlib.util.module_from_spec(aws_spec)
        aws_spec.loader.exec_module(aws_runner)
        for runner in (pilot, aws_runner):
            with self.subTest(runner=runner.__name__), tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / 'source'
                environment = pilot.command_environment(os.environ)
                subprocess.run(['git', '-c', 'init.templateDir=', 'init', '-q', str(root)],
                               env=environment, check=True, capture_output=True)
                self.assertFalse((root / '.git/info').exists())
                runner.exclude_generated_plan(root, '.pkglift/plan.json')
                runner.exclude_generated_plan(root, 'other-generated')
                (root / '.pkglift').mkdir()
                (root / '.pkglift/plan.json').write_text('{}')
                result = subprocess.run(['git', '-C', str(root), 'status', '--porcelain', '--untracked-files=all'],
                                        env=environment, check=True, capture_output=True, text=True)
                self.assertEqual(result.stdout, '')
                self.assertEqual((root / '.git/info/exclude').read_text(),
                                 '\n/.pkglift/plan.json\n\n/other-generated\n')

    def test_manual_refusal_actions_are_accepted(self):
        self.check()

    def test_auto_is_rejected_even_without_executable_actions(self):
        self.analysis['candidates'][0]['classification'] = 'AUTO'
        with self.assertRaisesRegex(RuntimeError, 'executable'):
            self.check()

    def test_non_auto_cannot_smuggle_executable_action(self):
        self.plan['entries'][0]['actions'].append({'removePod': {'name': 'FirebaseUI'}})
        with self.assertRaisesRegex(RuntimeError, 'executable'):
            self.check()

    def test_duplicate_entries_cannot_collapse_into_expected_set(self):
        self.plan['entries'].append(copy.deepcopy(self.plan['entries'][0]))
        with self.assertRaisesRegex(RuntimeError, 'Duplicate'):
            self.check()

    def test_wrong_project_or_workspace_cannot_satisfy_refusal(self):
        self.analysis['project']['workspacePath'] = '/other.xcworkspace'
        with self.assertRaisesRegex(RuntimeError, 'workspace'):
            self.check()
        self.analysis['project'].pop('workspacePath')
        self.plan['projectPath'] = '/other.xcodeproj'
        with self.assertRaisesRegex(RuntimeError, 'project'):
            self.check()

    def test_local_pod_becoming_review_fails_expected_boundary(self):
        self.plan['entries'][0]['classification'] = 'REVIEW'
        with self.assertRaisesRegex(RuntimeError, 'refusal changed'):
            self.check()

    def test_ignored_bytes_modes_and_symlink_changes_are_detected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.git').mkdir()
            (root / '.git/index').write_text('bookkeeping')
            (root / '.gitignore').write_text('ignored\n')
            item = root / 'ignored'
            item.write_text('before')
            baseline = pilot.snapshot(root)
            item.write_text('after')
            self.assertNotEqual(baseline, pilot.snapshot(root))
            item.write_text('before')
            item.chmod(0o755)
            self.assertNotEqual(baseline, pilot.snapshot(root))
            (root / 'link').symlink_to('ignored')
            linked = pilot.snapshot(root)
            self.assertEqual(linked['link'], ['symlink', 'ignored'])
            (root / '.git/index').write_text('different')
            self.assertEqual(linked, pilot.snapshot(root))  # Index is compared separately.

    def test_intake_rejects_changed_source_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'LICENSE').write_text('license')
            (root / 'Podfile').write_text('reviewed')
            case = {'root': '.', 'sourceEvidence': [{'path': 'Podfile', 'sha256': pilot.digest(root / 'Podfile')}],
                    'licenseAtPin': {'sha256': pilot.digest(root / 'LICENSE')}}
            pilot.validate_intake(root, case)
            (root / 'Podfile').write_text('changed')
            with self.assertRaisesRegex(RuntimeError, 'bytes changed'):
                pilot.validate_intake(root, case)

    def test_checkout_cannot_run_inherited_attribute_filters(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / 'repo'
            config = root / 'global-config'
            config.write_text('[filter "unreviewed"]\n smudge = false\n required = true\n')
            environment = pilot.command_environment(dict(os.environ, GIT_CONFIG_GLOBAL=str(config),
                GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='filter.unreviewed.smudge', GIT_CONFIG_VALUE_0='false'))
            self.assertNotIn('GIT_CONFIG_KEY_0', environment)
            def git(*args):
                return subprocess.run(['git', *args], cwd=repo, env=environment, check=True,
                                      capture_output=True, text=True)
            repo.mkdir()
            git('-c', 'init.templateDir=', 'init', '-q')
            (repo / '.gitattributes').write_text('payload filter=unreviewed\n')
            (repo / 'payload').write_text('reviewed bytes')
            git('add', '.')
            git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture')
            (repo / 'payload').unlink()
            git('checkout', '--', 'payload')
            self.assertEqual((repo / 'payload').read_text(), 'reviewed bytes')

    def test_runtime_gate_rejects_unverified_or_local_execution_before_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory).resolve()
            binary = temp / 'pkglift'
            binary.write_text('stub')
            binary.chmod(0o755)
            env = {'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted',
                   'PKGLIFT_ARTIFACT_SOURCE_SHA': 'a'*40, 'GITHUB_SHA': 'a'*40,
                   'PKGLIFT_ARTIFACT_RUN_ID': '123', 'GITHUB_RUN_ID': '123',
                   'PKGLIFT_ARTIFACT_RUN_ATTEMPT': '1', 'PKGLIFT_BINARY_SHA256': pilot.digest(binary),
                   'RUNNER_TEMP': str(temp)}
            pilot.runtime_contract(binary, temp / 'new', env)
            for key, value in [('RUNNER_ENVIRONMENT', 'self-hosted'), ('GITHUB_SHA', 'b'*40),
                               ('PKGLIFT_BINARY_SHA256', '0'*64), ('GITHUB_RUN_ID', '124')]:
                with self.subTest(key=key), self.assertRaises(RuntimeError):
                    pilot.runtime_contract(binary, temp / 'new', dict(env, **{key: value}))
            with self.assertRaises(RuntimeError):
                pilot.runtime_contract(binary, temp, env)
            with mock.patch.dict(os.environ, {}, clear=True), mock.patch('sys.argv', [str(pilot.__file__),
                    '--case', 'firebaseui-project', '--pkglift', str(binary), '--output', str(temp / 'new')]), \
                    mock.patch.object(pilot.subprocess, 'run') as run:
                with self.assertRaises(RuntimeError):
                    pilot.main()
                run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
