"""Unit tests for tool/verify_release_assets.py [P1-28, ADR-061]."""

from pathlib import Path
import sys
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


if __name__ == '__main__':
    unittest.main()
