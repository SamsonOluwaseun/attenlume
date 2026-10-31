"""P1-45 tests for fail-closed unattended coordination."""
import json
import mmap
from pathlib import Path
import tempfile
import unittest
from datetime import datetime, timezone, timedelta
from overnight_runner import (forbidden, quota_error, review_pass, review_status,
                              final_text, atomic_json, restore_local_documents, Relay)


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

    def test_p1_47_review_access_failure_is_not_a_code_finding(self):
        self.assertEqual(review_status('NIGHT_REVIEW_BLOCKED\nAccess denied'), 'blocked')
        self.assertEqual(review_status('NIGHT_REVIEW_CHANGES_REQUIRED\nregression'), 'changes requested')
        self.assertFalse(review_pass('NIGHT_REVIEW_PASS\nNIGHT_REVIEW_BLOCKED'))
        self.assertEqual(review_status('could not inspect'), 'blocked')

    def test_p1_47_mapped_tracked_pdf_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, target = root / 'source', root / 'worktree'
            for path in [source / 'docs/user-guide', target / 'docs/user-guide']:
                path.mkdir(parents=True)
            relative = 'docs/user-guide/guide.pdf'
            (source / relative).write_bytes(b'new guide')
            (target / relative).write_bytes(b'checked out guide')
            (source / 'docs/HANDOVER.md').write_text('private handover')
            with (target / relative).open('rb') as stream:
                with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ):
                    restore_local_documents(source, target, {relative})
                    self.assertEqual((target / relative).read_bytes(), b'checked out guide')
            self.assertEqual((target / 'docs/HANDOVER.md').read_text(), 'private handover')

    def test_p1_47_unattended_run_refused_without_an_alert_transport(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            logs = repo / 'tool/logs/test'
            config = {'repo': str(repo), 'logs': str(logs), 'checkpoint': 'test',
                      'deadline': (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()}
            relay = Relay(config)
            relay.run()
            self.assertEqual(relay.state['status'], 'blocked')
            self.assertEqual(relay.state['commands'], [])
            self.assertFalse((repo / 'tool/logs/overnight.lock').exists())


if __name__ == '__main__':
    unittest.main()
