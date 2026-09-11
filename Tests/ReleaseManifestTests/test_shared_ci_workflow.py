"""Mutate the real CI contract to prove shared compilation remains fail closed."""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = Path('.github/workflows/positive-e2e.yml')


class SharedCIWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            ['ruby', '-ryaml', '-rjson', '-e',
             'puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), aliases: true))',
             str(ROOT / WORKFLOW)], capture_output=True, text=True, check=True)
        cls.workflow = json.loads(result.stdout)
        if "true" in cls.workflow:
            cls.workflow["on"] = cls.workflow.pop("true")

    def validate(self, mutation=None, duplicate=False):
        with tempfile.TemporaryDirectory(prefix='pkglift-ci-policy-') as directory:
            root = Path(directory)
            shutil.copytree(ROOT / '.github', root / '.github')
            (root / 'Scripts').mkdir()
            for name in ('validate-repository-yaml.rb', 'run-pinned-pilot.sh'):
                shutil.copy2(ROOT / 'Scripts' / name, root / 'Scripts' / name)
            workflow = copy.deepcopy(self.workflow)
            if mutation:
                mutation(workflow)
            # JSON is valid YAML and keeps tests independent of a Python YAML dependency.
            (root / WORKFLOW).write_text(json.dumps(workflow, indent=2))
            if duplicate:
                (root / '.github/workflows/build.yml').write_text('name: Duplicate\n')
            return subprocess.run(['ruby', 'Scripts/validate-repository-yaml.rb'],
                                  cwd=root, capture_output=True, text=True)

    def reject(self, mutation, diagnostic):
        result = self.validate(mutation)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(diagnostic, result.stderr)

    def test_current_shared_workflow_passes(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_duplicate_entrypoint_is_rejected(self):
        result = self.validate(duplicate=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate ordinary CI entrypoint', result.stderr)

    def test_missing_or_conditional_producer_is_rejected(self):
        self.reject(lambda w: w['jobs'].pop('build_pilot_toolchain'), 'missing heavy job')
        self.reject(lambda w: w['jobs']['build_pilot_toolchain'].update({'if': 'false'}),
                    'must run unconditionally')

    def test_each_actual_compilation_test_and_registry_command_is_required(self):
        for command in ('swift build -j 2', 'swift test -j 2',
                        'swift run --skip-build pkglift registry validate',
                        'swift build -c release -j 2 --arch arm64'):
            with self.subTest(command=command):
                def mutate(w):
                    for step in w['jobs']['build_pilot_toolchain']['steps']:
                        if 'run' in step:
                            step['run'] = step['run'].replace(command, 'echo omitted')
                self.reject(mutate, 'producer must run')

    def test_producer_step_failure_cannot_be_ignored(self):
        def mutate(w):
            step = next(s for s in w['jobs']['build_pilot_toolchain']['steps']
                        if 'swift test -j 2' in s.get('run', ''))
            step['continue-on-error'] = True
        self.reject(mutate, 'producer steps must run unconditionally and fail closed')

    def test_gate_cannot_be_missing_skipped_or_accept_failure(self):
        for job in ('test', 'registry_gate', 'pinned_gate', 'gate'):
            with self.subTest(job=job):
                self.reject(lambda w: w['jobs'].pop(job), 'missing required stable gate')
                self.reject(lambda w: w['jobs'][job].update({'if': 'false'}), 'must use always()')
                def mutate(w):
                    for step in w['jobs'][job]['steps']:
                        if 'run' in step:
                            step['run'] = step['run'].replace("== 'success'", "!= 'failure'")
                self.reject(mutate, 'must require successful')

    def test_gate_must_depend_on_producer_and_cannot_ignore_failed_shell(self):
        self.reject(lambda w: w['jobs']['gate'].update({'needs': ['migrate-and-build']}),
                    'must require heavy job')
        def mutate(w):
            for step in w['jobs']['test']['steps']:
                if 'run' in step:
                    step['run'] = step['run'].replace('set -euo pipefail', 'set +e')
        self.reject(mutate, 'must require successful')

    def test_required_validation_cannot_be_path_filtered(self):
        key = 'on' if 'on' in self.workflow else 'true'
        self.reject(lambda w: w[key].update({'pull_request': {'paths': ['Sources/**']}}),
                    'without path filters')

    def test_each_consumer_requires_current_run_artifact(self):
        for job in ('analyze', 'migrate-and-build'):
            with self.subTest(job=job):
                def mutate(w):
                    step = next(s for s in w['jobs'][job]['steps']
                                if s.get('uses', '').startswith('actions/download-artifact@'))
                    step['with']['run-id'] = '123'
                self.reject(mutate, "must download this run's shared artifact")

    def test_each_consumer_must_verify_every_evidence_field(self):
        fields = ('ARCHIVE_SHA256', 'BINARY_SHA256', 'PRODUCER_ATTEMPT',
                  'REPOSITORY', 'RUN_ID', 'SOURCE_SHA')
        for job in ('analyze', 'migrate-and-build'):
            for field in fields:
                with self.subTest(job=job, field=field):
                    def mutate(w):
                        step = next(s for s in w['jobs'][job]['steps']
                                    if 'Scripts/verify-pilot-artifact.py' in s.get('run', ''))
                        step['env'].pop('PKGLIFT_EXPECTED_' + field)
                    self.reject(mutate, 'must verify all artifact identity')

    def test_verification_cannot_be_skipped_or_moved_after_pilot(self):
        def conditional(w):
            step = next(s for s in w['jobs']['migrate-and-build']['steps']
                        if 'Scripts/verify-pilot-artifact.py' in s.get('run', ''))
            step['if'] = 'false'
        self.reject(conditional, 'artifact and pilot steps must fail closed')
        def reordered(w):
            steps = w['jobs']['migrate-and-build']['steps']
            verifier = next(s for s in steps if 'Scripts/verify-pilot-artifact.py' in s.get('run', ''))
            steps.remove(verifier)
            steps.append(verifier)
        self.reject(reordered, 'must verify the downloaded artifact before running pilots')

    def test_required_check_names_cannot_change(self):
        for job in ('build_pilot_toolchain', 'test', 'registry_gate', 'pinned_gate', 'gate'):
            with self.subTest(job=job):
                diagnostic = 'build check name' if job == 'build_pilot_toolchain' else 'stable gate'
                self.reject(lambda w: w['jobs'][job].update({'name': 'wrong-name'}), diagnostic)

    def test_pilot_or_verifier_failure_cannot_be_ignored(self):
        for job in ('analyze', 'migrate-and-build'):
            for marker in ('Scripts/verify-pilot-artifact.py',
                           'Scripts/run-pinned-pilot.sh' if job == 'analyze'
                           else 'Scripts/run-positive-e2e-pilot.sh'):
                with self.subTest(job=job, marker=marker):
                    def mutate(w):
                        step = next(s for s in w['jobs'][job]['steps']
                                    if marker in s.get('run', ''))
                        step['continue-on-error'] = True
                    self.reject(mutate, 'artifact and pilot steps must fail closed')

    def test_real_gate_shells_reject_failed_cancelled_missing_and_skipped_results(self):
        for job in ('test', 'registry_gate', 'pinned_gate', 'gate'):
            for step in self.workflow['jobs'][job]['steps']:
                if 'run' not in step:
                    continue
                variables = [key for key, value in step.get('env', {}).items()
                             if '.result' in value]
                self.assertTrue(variables)
                environment = dict(os.environ, **{key: 'success' for key in variables})
                result = subprocess.run(['bash', '-c', step['run']], env=environment,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                for variable in variables:
                    for status in ('failure', 'cancelled', 'skipped', ''):
                        with self.subTest(job=job, variable=variable, status=status):
                            failed_environment = dict(environment, **{variable: status})
                            result = subprocess.run(['bash', '-c', step['run']],
                                                    env=failed_environment,
                                                    capture_output=True, text=True)
                            self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_missing_pilot_case_still_fails(self):
        self.reject(lambda w: w['jobs']['analyze']['strategy']['matrix']['include'].pop(),
                    'missing matrix entry for supported pilot case')


if __name__ == '__main__':
    unittest.main()
