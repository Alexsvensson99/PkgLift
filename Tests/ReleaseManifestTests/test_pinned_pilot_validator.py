"""Focused policy tests for the AWS Grid Feed source-only pilot contract."""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / 'Scripts/validate-pinned-pilot.rb'
CASE = 'aws_grid_feed_source_only'
REASON = 'target_header_import_evidence_incomplete'


def record(name, classification, reason_codes=()):
    reasons = [f'{code} message' for code in reason_codes]
    return {
        'pod': {'name': name, 'isDirect': True},
        'classification': classification,
        'reasons': reasons,
        'reasonDetails': [{'code': code, 'message': message} for code, message in zip(reason_codes, reasons)],
    }


def plan_record(candidate):
    return {
        'podName': candidate['pod']['name'],
        'classification': candidate['classification'],
        'reasons': copy.deepcopy(candidate['reasons']),
        'reasonDetails': copy.deepcopy(candidate['reasonDetails']),
    }


class PinnedPilotValidatorTests(unittest.TestCase):
    def fixture(self):
        candidates = [record('SDWebImage', 'REVIEW', [REASON]), record('AmazonIVSPlayer', 'REVIEW')]
        analysis = {'portableOutput': {'version': 1}, 'candidates': candidates}
        plan = {'portableOutput': {'version': 1}, 'entries': [plan_record(candidate) for candidate in candidates]}
        return analysis, plan

    def validate(self, analysis, plan, portable_analysis=None, portable_plan=None, clean=True):
        portable_analysis = analysis if portable_analysis is None else portable_analysis
        portable_plan = plan if portable_plan is None else portable_plan
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = {
                'analysis': root / 'analysis.json', 'plan': root / 'plan.json',
                'portable_analysis': root / 'portable-analysis.json', 'portable_plan': root / 'portable-plan.json',
                'dry_run': root / 'dry-run.txt', 'report': root / 'report',
            }
            for key, payload in [('analysis', analysis), ('plan', plan), ('portable_analysis', portable_analysis), ('portable_plan', portable_plan)]:
                paths[key].write_text(json.dumps(payload), encoding='utf-8')
            paths['dry_run'].write_text('dry run', encoding='utf-8')
            environment = dict(os.environ, PILOT_DRY_RUN_CLEAN='true' if clean else 'false')
            return subprocess.run(
                ['ruby', str(VALIDATOR), CASE, str(paths['analysis']), str(paths['plan']), str(paths['dry_run']),
                 str(root), str(paths['report']), str(paths['portable_analysis']), str(paths['portable_plan'])],
                capture_output=True, text=True, env=environment,
            )

    def test_valid_exact_review_refusal_passes(self):
        analysis, plan = self.fixture()
        self.assertEqual(self.validate(analysis, plan).returncode, 0)

    def test_sdwebimage_auto_is_rejected(self):
        analysis, plan = self.fixture()
        analysis['candidates'][0]['classification'] = 'AUTO'
        plan['entries'][0]['classification'] = 'AUTO'
        self.assertNotEqual(self.validate(analysis, plan).returncode, 0)

    def test_missing_or_extra_sdwebimage_reason_is_rejected(self):
        for codes in ([], ['unexpected_reason'], [REASON, 'unexpected_reason']):
            with self.subTest(codes=codes):
                analysis, plan = self.fixture()
                candidate = analysis['candidates'][0]
                candidate['reasons'] = [f'{code} message' for code in codes]
                candidate['reasonDetails'] = [{'code': code, 'message': f'{code} message'} for code in codes]
                plan['entries'][0] = plan_record(candidate)
                self.assertNotEqual(self.validate(analysis, plan).returncode, 0)

    def test_extra_auto_or_missing_dependency_is_rejected(self):
        analysis, plan = self.fixture()
        extra = record('Unexpected', 'AUTO')
        analysis['candidates'].append(extra)
        plan['entries'].append(plan_record(extra))
        self.assertNotEqual(self.validate(analysis, plan).returncode, 0)
        analysis, plan = self.fixture()
        analysis['candidates'].pop()
        plan['entries'].pop()
        self.assertNotEqual(self.validate(analysis, plan).returncode, 0)

    def test_duplicate_portable_records_cannot_hide_auto(self):
        analysis, plan = self.fixture()
        portable_analysis = copy.deepcopy(analysis)
        duplicate = copy.deepcopy(portable_analysis['candidates'][0])
        duplicate['classification'] = 'AUTO'
        portable_analysis['candidates'].insert(0, duplicate)
        self.assertNotEqual(self.validate(analysis, plan, portable_analysis=portable_analysis).returncode, 0)
        portable_plan = copy.deepcopy(plan)
        duplicate = copy.deepcopy(portable_plan['entries'][0])
        duplicate['classification'] = 'AUTO'
        portable_plan['entries'].insert(0, duplicate)
        self.assertNotEqual(self.validate(analysis, plan, portable_plan=portable_plan).returncode, 0)

    def test_executable_portable_parity_and_dry_run_clean_are_required(self):
        analysis, plan = self.fixture()
        portable_analysis = copy.deepcopy(analysis)
        portable_analysis['candidates'][1]['classification'] = 'AUTO'
        self.assertNotEqual(self.validate(analysis, plan, portable_analysis=portable_analysis).returncode, 0)
        self.assertNotEqual(self.validate(analysis, plan, clean=False).returncode, 0)


if __name__ == '__main__':
    unittest.main()
