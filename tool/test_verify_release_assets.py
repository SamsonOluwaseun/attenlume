"""Unit tests for tool/verify_release_assets.py [P1-28, ADR-061]."""

from pathlib import Path
import sys
import os
import shutil
import subprocess
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from verify_release_assets import (
    CANONICAL_ASSETS,
    CHECKSUMS_FILENAME,
    compute_sha256,
    generate_checksums,
    verify_checksums_file,
    write_checksums_file,
)


class VerifyReleaseAssetsTests(unittest.TestCase):
    def test_p1_28_canonical_assets_defined(self):
        self.assertIn('attenlume-android.apk', CANONICAL_ASSETS)
        self.assertIn('attenlume-windows-setup.exe', CANONICAL_ASSETS)

    def test_p1_28_generate_and_verify_checksums(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            dir_path = Path(temp_dir)
            apk = dir_path / 'attenlume-android.apk'
            exe = dir_path / 'attenlume-windows-setup.exe'

            apk.write_bytes(b'dummy-apk-content')
            exe.write_bytes(b'dummy-installer-content')

            out_file = write_checksums_file(dir_path)
            self.assertTrue(out_file.is_file())
            self.assertEqual(out_file.name, CHECKSUMS_FILENAME)

            ok, messages = verify_checksums_file(dir_path)
            self.assertTrue(ok)
            self.assertTrue(any('attenlume-android.apk: OK' in m for m in messages))
            self.assertTrue(any('attenlume-windows-setup.exe: OK' in m for m in messages))

    def test_p1_28_generate_fails_on_missing_asset(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            dir_path = Path(temp_dir)
            apk = dir_path / 'attenlume-android.apk'
            apk.write_bytes(b'dummy-apk-content')
            # attenlume-windows-setup.exe is missing

            with self.assertRaises(FileNotFoundError):
                generate_checksums(dir_path)

    def test_p1_28_verify_fails_on_tampered_content(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            dir_path = Path(temp_dir)
            apk = dir_path / 'attenlume-android.apk'
            exe = dir_path / 'attenlume-windows-setup.exe'

            apk.write_bytes(b'initial-apk-content')
            exe.write_bytes(b'initial-installer-content')

            write_checksums_file(dir_path)

            # Tamper with the APK
            apk.write_bytes(b'tampered-apk-content')

            ok, messages = verify_checksums_file(dir_path)
            self.assertFalse(ok)
            self.assertTrue(any('FAILED' in m and 'attenlume-android.apk' in m for m in messages))

    def test_p1_28_rejects_incomplete_or_unsafe_manifests(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            directory = Path(temp_dir)
            for name in CANONICAL_ASSETS:
                (directory / name).write_bytes(b'asset')
            lines = generate_checksums(directory)
            invalid = {
                'empty': '',
                'missing': lines[0],
                'duplicate': ''.join(lines) + lines[0],
                'extra': ''.join(lines) + lines[0].replace(CANONICAL_ASSETS[0], 'extra.apk'),
                'traversal': ''.join(lines).replace(CANONICAL_ASSETS[0], '../' + CANONICAL_ASSETS[0]),
                'absolute': ''.join(lines).replace(CANONICAL_ASSETS[0], '/tmp/asset.apk'),
                'backslash': ''.join(lines).replace(CANONICAL_ASSETS[0], '..\\asset.apk'),
                'hash': ''.join(lines).replace(lines[0][:64], 'x' * 64),
                'short_hash': ''.join(lines).replace(lines[0][:64], 'a' * 63),
                'comment_only': '# no assets\n',
            }
            for name, manifest in invalid.items():
                with self.subTest(name=name):
                    (directory / CHECKSUMS_FILENAME).write_text(manifest, encoding='utf-8')
                    ok, messages = verify_checksums_file(directory)
                    self.assertFalse(ok)
                    self.assertTrue(messages)

    def test_p1_28_reports_missing_unreadable_and_invalid_encoding(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            directory = Path(temp_dir)
            self.assertFalse(verify_checksums_file(directory)[0])
            manifest = directory / CHECKSUMS_FILENAME
            manifest.write_bytes(b'\xff')
            self.assertFalse(verify_checksums_file(directory)[0])
            manifest.write_text('0' * 64 + '  ' + CANONICAL_ASSETS[0] + '\n', encoding='utf-8')
            ok, messages = verify_checksums_file(directory)
            self.assertFalse(ok)
            self.assertTrue(any('FAILED' in message for message in messages))


class ReleaseWorkflowShellTests(unittest.TestCase):
    bash = ('C:/Program Files/Git/bin/bash.exe' if Path('C:/Program Files/Git/bin/bash.exe').exists() else shutil.which('bash'))

    def run_step(self, name, directory, values, prefix=""):
        workflow = (Path(__file__).resolve().parents[1] / '.github/workflows/release.yml').read_text()
        step = workflow.split('      - name: ' + name + '\n', 1)[1].split('\n      - name:', 1)[0]
        body = step.split('        run: |\n', 1)[1]
        script = '\n'.join(line[10:] for line in body.splitlines())
        env = os.environ.copy()
        env.update(values)
        return subprocess.run([self.bash, '-c', prefix + script], cwd=directory, env=env, capture_output=True, text=True)

    def test_p1_28_metadata_treats_payload_as_data_and_rejects_unsafe_tags(self):
        if not self.bash:
            self.skipTest('Bash is required for workflow execution tests')
        with tempfile.TemporaryDirectory() as temp_dir:
            directory = Path(temp_dir)
            (directory / 'pubspec.yaml').write_text('version: 1.2.3+4\n')
            output = directory / 'output'
            values = {'INPUT_TAG': 'v1.2.3', 'INPUT_TITLE': '$(touch injected); "quoted"', 'GITHUB_OUTPUT': output.as_posix()}
            result = self.run_step('Determine version and release metadata', directory, values)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('title=' + values['INPUT_TITLE'], output.read_text())
            self.assertFalse((directory / 'injected').exists())
            for tag, title in [('v1.2.3; touch injected', ''), ('--draft=false', ''), ('v1.2.3', 'title\nother=value')]:
                with self.subTest(tag=tag, title=title):
                    output.write_text('')
                    result = self.run_step('Determine version and release metadata', directory, {**values, 'INPUT_TAG': tag, 'INPUT_TITLE': title})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(output.read_text(), '')
                    self.assertFalse((directory / 'injected').exists())

    def test_p1_28_release_is_always_draft_and_title_is_one_argument(self):
        if not self.bash:
            self.skipTest('Bash is required for workflow execution tests')
        with tempfile.TemporaryDirectory() as temp_dir:
            directory = Path(temp_dir)
            title = '$(touch injected); "owner title"'
            values = {'RELEASE_TAG': 'v1.2.3', 'RELEASE_TITLE': title, 'RELEASE_TARGET': 'abcdef', 'RELEASE_PRERELEASE': 'false'}
            result = self.run_step('Create GitHub Draft Release', directory, values,
                                   "gh() { printf '%s\\n' \"$@\" > args; };\n")
            self.assertEqual(result.returncode, 0, result.stderr)
            args = (directory / 'args').read_text().splitlines()
            self.assertIn('--draft', args)
            self.assertFalse(any(arg.startswith('--draft=') for arg in args))
            self.assertEqual(args[args.index('--title') + 1], title)
            self.assertFalse((directory / 'injected').exists())

    def test_p1_28_each_missing_signing_input_fails_before_writing(self):
        if not self.bash:
            self.skipTest('Bash is required for workflow execution tests')
        values = dict.fromkeys(('KEYSTORE_BASE64', 'STORE_PASSWORD', 'KEY_ALIAS', 'KEY_PASSWORD'), 'test-value-never-log')
        with tempfile.TemporaryDirectory() as temp_dir:
            directory = Path(temp_dir)
            for missing in values:
                with self.subTest(missing=missing):
                    result = self.run_step('Configure Android release signing', directory, {**values, missing: ''})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn('test-value-never-log', result.stdout + result.stderr)
                    self.assertFalse((directory / 'android').exists())


if __name__ == '__main__':
    unittest.main()
