"""Guard the manual upstream execution boundary independently of ordinary CI."""
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/real-project-qualification.yml'


def load_workflow():
    return json.loads(subprocess.check_output(['ruby', '-ryaml', '-rjson', '-e',
        'puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), aliases: true))', str(WORKFLOW)], text=True))


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = load_workflow()

    def test_only_manual_dispatch_and_read_only_permission(self):
        workflow = self.workflow
        self.assertEqual(workflow.get('on', workflow.get('true')), {'workflow_dispatch': None})
        self.assertEqual(workflow['permissions'], {'contents': 'read'})
        self.assertFalse(workflow['concurrency']['cancel-in-progress'])
        self.assertNotIn('${{ secrets.', WORKFLOW.read_text())

    def test_controls_gate_aws_and_never_execute_build_or_apply(self):
        jobs = self.workflow['jobs']
        self.assertEqual(set(jobs['aws_partial_migration']['needs']), {'build_pilot_toolchain', 'refusal_controls'})
        self.assertEqual(jobs['refusal_controls']['strategy']['matrix']['case'],
                         ['firebaseui-project', 'hammerspoon-workspace'])
        commands = '\n'.join(s.get('run', '') for s in jobs['refusal_controls']['steps'])
        self.assertIn('run-real-project-refusal.py', commands)
        for forbidden in ['--apply', 'pod install', 'xcodebuild', 'run-real-project-aws.py']:
            self.assertNotIn(forbidden, commands)
        gate = jobs['qualification_gate']
        self.assertEqual(gate['if'], 'always()')
        self.assertEqual(set(gate['needs']), {'build_pilot_toolchain', 'refusal_controls', 'aws_partial_migration'})
        for variable in ['BUILD_RESULT', 'REFUSAL_RESULT', 'AWS_RESULT']:
            self.assertIn(f'[[ "${variable}" == success ]]', gate['steps'][0]['run'])

    def test_each_consumer_checks_same_run_artifact_and_uploads_reports_only(self):
        jobs = self.workflow['jobs']
        for job_id, directory in [('refusal_controls', 'pkglift-g3-refusal'), ('aws_partial_migration', 'pkglift-g3-aws')]:
            job = jobs[job_id]
            self.assertEqual(job['runs-on'], 'macos-15')
            steps = job['steps']
            verify = next(s for s in steps if 'verify-pilot-artifact.py' in s.get('run', ''))
            for key in ['ARCHIVE_SHA256', 'BINARY_SHA256', 'PRODUCER_ATTEMPT', 'REPOSITORY', 'RUN_ID', 'SOURCE_SHA']:
                self.assertIn('PKGLIFT_EXPECTED_' + key, verify['env'])
            upload = next(s for s in steps if 'actions/upload-artifact@' in s.get('uses', ''))
            self.assertEqual(upload['with']['path'], '${{ runner.temp }}/' + directory + '/report')
            self.assertEqual(upload['if'], 'always()')
        for job in jobs.values():
            for step in job['steps']:
                if step.get('uses', '').startswith('actions/checkout@'):
                    self.assertIs(step['with']['persist-credentials'], False)
                if 'uses' in step:
                    self.assertRegex(step['uses'], r'@[0-9a-f]{40}$')


if __name__ == '__main__':
    unittest.main()
