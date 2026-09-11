from pathlib import Path
import runpy
import unittest

MODULE = runpy.run_path(str(Path(__file__).resolve().parents[2] / 'Scripts/ensure-release-distribution.py'))
ensure = MODULE['ensure_distribution']
Error = MODULE['DistributionError']
SHA = 'a' * 40
REPO = 'owner/repo'


def run(identifier=1, status='completed', conclusion='success', **changes):
    value = dict(id=identifier, run_attempt=1, head_sha=SHA, head_branch='main',
                 event='workflow_dispatch', path='.github/workflows/release.yml',
                 repository={'full_name': REPO}, status=status, conclusion=conclusion)
    value.update(changes)
    return value


class Fake:
    def __init__(self, listings, states=None, expired=False):
        self.listings = list(listings)
        self.states = states or {}
        self.expired = expired
        self.posts = 0
        self.now = 0
        self.main = SHA
        self.polled = []

    def runs(self):
        return self.listings.pop(0) if len(self.listings) > 1 else self.listings[0]

    def run(self, identifier):
        self.polled.append(identifier)
        return self.states.get(identifier, run(identifier))

    def artifacts(self, identifier):
        return [dict(name=f'pkglift-macos-arm64-{SHA}', expired=self.expired and identifier == 1, size_in_bytes=20)]

    def main_sha(self):
        return self.main

    def dispatch(self):
        self.posts += 1

    def sleep(self, delay):
        self.now += delay

    def execute(self):
        return ensure(self, SHA, REPO, clock=lambda: self.now, sleep=self.sleep, timeout=60)


class DistributionTests(unittest.TestCase):
    def test_reuses_success_without_dispatch(self):
        api = Fake([[run()]])
        self.assertEqual(api.execute(), 1)
        self.assertEqual(api.posts, 0)

    def test_attaches_to_active_instead_of_old_success(self):
        api = Fake([[run(), run(2, 'waiting', None)]])
        self.assertEqual(api.execute(), 2)
        self.assertEqual(api.posts, 0)

    def test_expired_artifact_dispatches_once_and_waits_for_visibility(self):
        api = Fake([[run()], [run()], [run(), run(2)]], expired=True)
        self.assertEqual(api.execute(), 2)
        self.assertEqual(api.posts, 1)
        self.assertEqual(api.polled, [2])
        self.assertGreater(api.now, 0)

    def test_failed_run_dispatches_once(self):
        api = Fake([[run(conclusion='failure')], [run(conclusion='failure'), run(2)]])
        self.assertEqual(api.execute(), 2)
        self.assertEqual(api.posts, 1)

    def test_selected_failure_never_falls_back_to_old_success(self):
        api = Fake([[run(), run(2, 'in_progress', None)]], {2: run(2, conclusion='failure')})
        with self.assertRaises(Error): api.execute()
        self.assertEqual(api.posts, 0)
        self.assertEqual(api.polled, [2])

    def test_rejects_changed_identity_or_attempt(self):
        for change in ({'head_sha': 'b'*40}, {'run_attempt': 2}, {'id': 3}):
            with self.subTest(change=change):
                api = Fake([[run(2, 'in_progress', None)]], {2: run(2, **change)} if 'id' not in change else {2: run(3)})
                with self.assertRaises(Error): api.execute()

    def test_wrong_metadata_cannot_be_reused(self):
        for change in ({'head_sha':'b'*40}, {'head_branch':'other'}, {'event':'push'},
                       {'path':'.github/workflows/other.yml'}, {'repository':{'full_name':'other/repo'}}):
            with self.subTest(change=change):
                api = Fake([[run(**change)], [run(2)]])
                self.assertEqual(api.execute(), 2)
                self.assertEqual(api.posts, 1)

    def test_moved_main_prevents_dispatch(self):
        api = Fake([[]]); api.main = 'b'*40
        with self.assertRaises(Error): api.execute()
        self.assertEqual(api.posts, 0)

    def test_delayed_visibility_times_out_without_repeated_posts(self):
        api = Fake([[]])
        with self.assertRaises(Error): api.execute()
        self.assertEqual(api.posts, 1)

    def test_ambiguous_new_runs_fail(self):
        api = Fake([[], [run(2), run(3)]])
        with self.assertRaises(Error): api.execute()
        self.assertEqual(api.posts, 1)

    def test_api_error_is_not_treated_as_absence(self):
        api = Fake([[run()]])
        def fail(_): raise OSError('network')
        api.artifacts = fail
        with self.assertRaises(OSError): api.execute()
        self.assertEqual(api.posts, 0)

    def test_uncertain_dispatch_is_not_retried(self):
        api = Fake([[]])
        def dispatch():
            api.posts += 1
            raise OSError('response lost')
        api.dispatch = dispatch
        with self.assertRaises(OSError): api.execute()
        self.assertEqual(api.posts, 1)

    def test_active_run_remains_pinned_across_polls(self):
        api = Fake([[run(2, 'waiting', None)]])
        states = [run(2, 'in_progress', None), run(2)]
        def poll(identifier):
            api.polled.append(identifier)
            return states.pop(0)
        api.run = poll
        self.assertEqual(api.execute(), 2)
        self.assertEqual(api.polled, [2, 2])
        self.assertEqual(api.posts, 0)

    def test_duplicate_artifacts_fail_without_dispatch(self):
        api = Fake([[run()]])
        original = api.artifacts
        api.artifacts = lambda identifier: original(identifier) * 2
        with self.assertRaises(Error): api.execute()
        self.assertEqual(api.posts, 0)

    def test_selected_success_without_artifact_fails(self):
        api = Fake([[run(2, 'waiting', None)]])
        api.artifacts = lambda _: []
        with self.assertRaises(Error): api.execute()
        self.assertEqual(api.posts, 0)

    def test_history_paginates_and_fails_if_truncated(self):
        api = MODULE['GitHub'](REPO, 'unused')
        paths = []
        def request(path):
            paths.append(path)
            return {'workflow_runs': [run()] * 100 if len(paths) == 1 else [run(2)]}
        api.request = request
        self.assertEqual(len(api.runs()), 101)
        self.assertIn('page=2', paths[1])
        api.request = lambda _: {'workflow_runs':[run()]*100}
        with self.assertRaises(Error): api.runs()

    def test_workflow_uses_one_orchestrator_and_preserves_publication_gate(self):
        root = Path(__file__).resolve().parents[2]
        workflow = (root/'.github/workflows/publish-release-manifest.yml').read_text()
        self.assertEqual(workflow.count('run: python3 Scripts/ensure-release-distribution.py'), 1)
        self.assertNotIn('      - name: Dispatch Signed Distribution Validation', workflow)
        self.assertIn('environment: production-release', workflow)
        self.assertIn('steps.signing_run.outputs.run_id', workflow)


if __name__ == '__main__': unittest.main()
