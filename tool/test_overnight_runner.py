"""P1-45 tests for fail-closed unattended coordination."""
import json
from pathlib import Path
import tempfile
import unittest
from overnight_runner import forbidden, quota_error, review_pass, final_text, atomic_json


class OvernightTests(unittest.TestCase):
    def test_p1_45_review_requires_exact_final_marker(self):
        self.assertTrue(review_pass('Reviewed.\nNIGHT_REVIEW_PASS\n'))
        self.assertFalse(review_pass('Do not print NIGHT_REVIEW_PASS unless safe'))
        self.assertFalse(review_pass('NIGHT_REVIEW_CHANGES_REQUIRED'))

    def test_p1_45_protect_supervisor_and_credentials(self):
        self.assertEqual(forbidden(['lib/new.dart', '.github/workflows/release.yml']), [])
        self.assertEqual(len(forbidden(['tool/overnight_runner.py', 'android/key.properties',
                                       'cert.p12', 'AGENTS.md', 'lib/.env'])), 5)

    def test_p1_45_quota_detection_ignores_quoted_source(self):
        with tempfile.TemporaryDirectory() as directory:
            out, err = Path(directory) / 'out', Path(directory) / 'err'
            out.write_text(json.dumps({'type': 'item.completed', 'item': {'text': 'quota error 429 in docs'}}))
            err.write_text('sandbox: workspace-write\n')
            self.assertFalse(quota_error(out, err))
            out.write_text(json.dumps({'type': 'error', 'message': 'usage limit reached'}))
            self.assertTrue(quota_error(out, err))
            out.write_text('{}')
            err.write_text('AGY_ERROR: RESOURCE_EXHAUSTED code 429')
            self.assertTrue(quota_error(out, err))

    def test_p1_45_antigravity_empty_response_is_not_success(self):
        with tempfile.TemporaryDirectory() as directory:
            out, final = Path(directory) / 'out', Path(directory) / 'final'
            out.write_text(json.dumps({'status': 'SUCCESS', 'response': '', 'denied_actions': ['command']}))
            self.assertEqual(final_text('antigravity', out, final), '')
            out.write_text(json.dumps({'status': 'SUCCESS', 'response': 'Ready'}))
            self.assertEqual(final_text('antigravity', out, final), 'Ready')

    def test_p1_45_atomic_state_is_parseable(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'state.json'
            atomic_json(path, {'status': 'running'})
            atomic_json(path, {'status': 'finished'})
            self.assertEqual(json.loads(path.read_text())['status'], 'finished')
            self.assertFalse(path.with_suffix('.json.tmp').exists())


if __name__ == '__main__':
    unittest.main()
