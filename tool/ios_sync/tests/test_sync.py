"""P1-43: prove update planning cannot overwrite the working Mac copy."""

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from compare_on_mac import classify, plan, validate_package
from sync_common import allowed, normalise, safe_path, sha
import export_update


class SyncTests(unittest.TestCase):
    def test_p1_43_icon_regeneration_helper_is_transferred(self):
        self.assertTrue(allowed('tool/brand/prepare_icons.dart'))
        self.assertFalse(allowed('tool/brand/signing.key'))
        self.assertFalse(allowed('tool/brand/private.jks'))

    def test_p1_43_mac_only_edits_survive(self):
        self.assertEqual(classify(b'base', b'base', b'Mac fix', 'lib/a.dart'),
                         ('preserved_local', None))

    def test_p1_43_unchanged_local_gets_upstream(self):
        self.assertEqual(classify(b'old', b'new', b'old', 'lib/a.dart'), ('update', b'new'))
        self.assertEqual(classify(None, b'new', None, 'lib/a.dart'), ('add', b'new'))
        self.assertEqual(classify(b'old', None, b'old', 'lib/a.dart'), ('delete', None))

    def test_p1_43_overlapping_changes_conflict(self):
        action, content = classify(b'a\n', b'Windows\n', b'Mac\n', 'lib/a.dart')
        self.assertEqual(action, 'conflict')
        self.assertIn(b'<<<<<<<', content)

    def test_p1_43_nonoverlapping_edits_merge(self):
        base = b'one\ntwo\nthree\nfour\nfive\nsix\nseven\n'
        incoming = base.replace(b'one', b'Windows')
        local = base.replace(b'seven', b'Mac')
        self.assertEqual(classify(base, incoming, local, 'lib/a.dart'),
                         ('merged', incoming.replace(b'seven', b'Mac')))

    def test_p1_43_modified_delete_and_add_conflicts(self):
        for versions in [(b'a', None, b'Mac'), (None, b'Windows', b'Mac'),
                         (b'a', b'Windows', None)]:
            self.assertEqual(classify(*versions, 'lib/a.dart')[0], 'conflict')

    def test_p1_43_native_runner_needs_review(self):
        self.assertEqual(classify(b'old', b'new', b'old', 'ios/Runner/Info.plist'),
                         ('native_review', None))
        self.assertEqual(classify(b'old', b'old', b'Mac signed', 'ios/Runner/Info.plist'),
                         ('preserved_local', None))

    def test_p1_43_binary_conflict_and_line_endings(self):
        self.assertEqual(classify(b'\0a', b'\0b', b'\0c', 'assets/icon.png')[0], 'conflict')
        self.assertEqual(classify(b'a\n', b'a\r\n', b'Mac', 'lib/a.dart')[0], 'preserved_local')
        self.assertEqual(normalise(b'\0\r\n'), b'\0\r\n')

    def test_p1_43_paths_and_secrets_rejected(self):
        for path in ['../outside', '/lib/a.dart', 'lib/../../secret', 'C:/secret',
                     'lib\\..\\secret', 'ios/Pods/a', 'android/key.properties',
                     'assets/private.p12', 'lib/.env', 'tool/ios_sync/__pycache__/a.pyc']:
            self.assertFalse(allowed(path), path)

    def make_package(self, root):
        pack, project = root / 'pack', root / 'project'
        project.mkdir()
        (project / 'pubspec.yaml').write_text('name: attenlume')
        relative = 'lib/a.dart'
        for side, content in [('base', b'old'), ('incoming', b'new')]:
            path = pack / side / relative
            path.parent.mkdir(parents=True)
            path.write_bytes(content)
        (project / 'lib').mkdir()
        (project / relative).write_bytes(b'old')
        manifest = {'format': 1, 'package_id': 'test', 'base_files': {relative: sha(b'old')},
                    'incoming_files': {relative: sha(b'new')}}
        (pack / 'UPDATE.json').write_text(json.dumps(manifest))
        return pack, project

    def test_p1_43_planning_never_writes_to_working_project(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            pack, project = self.make_package(root)
            report = plan(pack, project, root / 'review')
            self.assertEqual(report['counts'], {'update': 1})
            self.assertEqual((project / 'lib/a.dart').read_bytes(), b'old')
            self.assertEqual((root / 'review/proposed/lib/a.dart').read_bytes(), b'new')
            with self.assertRaises(FileExistsError):
                plan(pack, project, root / 'review')

    def test_p1_43_tampered_package_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            pack, _ = self.make_package(Path(temp))
            (pack / 'incoming/lib/a.dart').write_bytes(b'corrupt')
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                validate_package(pack)

    def test_p1_43_review_cannot_be_inside_working_project(self):
        with tempfile.TemporaryDirectory() as temp:
            pack, project = self.make_package(Path(temp))
            with self.assertRaises(ValueError):
                plan(pack, project, project / 'review')

    def test_p1_43_symlink_escape_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'project').mkdir()
            (root / 'outside').mkdir()
            try:
                (root / 'project/lib').symlink_to(root / 'outside', target_is_directory=True)
            except OSError:
                self.skipTest('Symlink creation unavailable for this Windows account')
            with self.assertRaises(ValueError):
                safe_path(root / 'project', 'lib/a.dart')

    def test_p1_43_exports_are_cumulative_and_stale_source_is_detected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            repo, output = root / 'repo', root / 'updates'
            repo.mkdir()
            export_update.git(repo, 'init')
            (repo / 'lib').mkdir()
            (repo / 'pubspec.yaml').write_text('name: attenlume\nversion: 0.1.5+6\n')
            (repo / 'lib/a.dart').write_text('original\n')
            export_update.git(repo, 'add', '.')
            export_update.git(repo, '-c', 'user.name=Samlytics Data Services', '-c',
                              'user.email=test@localhost', 'commit', '-m', 'test baseline')
            baseline = export_update.git(repo, 'rev-parse', 'HEAD').decode().strip()
            with patch.object(export_update, 'BASELINE', baseline):
                first = export_update.export(repo, output)
                self.assertEqual(export_update.export(repo, output, check=True), first)
                (repo / 'lib/a.dart').write_text('update one\n')
                with self.assertRaisesRegex(ValueError, 'stale'):
                    export_update.export(repo, output, check=True)
                export_update.export(repo, output)
                (repo / 'lib/a.dart').write_text('update two\n')
                latest = export_update.export(repo, output)
                self.assertEqual((latest / 'base/lib/a.dart').read_text(), 'original\n')
                self.assertEqual((latest / 'incoming/lib/a.dart').read_text(), 'update two\n')
                # A Mac that skipped update one still gets update two.
                project = root / 'mac'
                project.mkdir()
                (project / 'pubspec.yaml').write_bytes((repo / 'pubspec.yaml').read_bytes())
                (project / 'lib').mkdir()
                (project / 'lib/a.dart').write_text('original\n')
                report = plan(latest, project, root / 'review')
                self.assertEqual(report['counts']['update'], 1)
                pointer = json.loads((output / 'LATEST.json').read_text())
                (output / pointer['archive']).write_bytes(b'broken transfer')
                with self.assertRaisesRegex(ValueError, 'archive hash mismatch'):
                    export_update.export(repo, output, check=True)


if __name__ == '__main__':
    unittest.main()
