"""Public helper command: exact owned cache deletion and fail-closed substitutions."""
import json, os, pathlib, subprocess, tempfile, unittest
HELPER = pathlib.Path(__file__).with_name('remove-owned-cache.py')
class OwnedCacheBoundary(unittest.TestCase):
    def test_exact_leaf_removed_but_protected_sibling_preserved_and_symlink_refused(self):
        with tempfile.TemporaryDirectory(prefix='StillChromeProbe-') as temporary:
            root = pathlib.Path(temporary).resolve()
            cache = root / 'custom' / 'Default' / 'Cache' / 'Cache_Data'
            cache.mkdir(parents=True)
            protected = root / 'Cookies'; protected.write_bytes(b'protected')
            leaf = cache / 'asset'; leaf.write_bytes(b'cache')
            s = leaf.stat()
            manifest = [{'path': str(leaf), 'dev': s.st_dev, 'ino': s.st_ino, 'size': s.st_size, 'mtimeMs': s.st_mtime_ns / 1000000}]
            result = subprocess.run(['python3', str(HELPER), str(root), str(cache)], input=json.dumps(manifest), text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(leaf.exists()); self.assertEqual(protected.read_bytes(), b'protected')
            leaf.symlink_to(protected)
            result = subprocess.run(['python3', str(HELPER), str(root), str(cache)], input=json.dumps(manifest), text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0); self.assertIn('Refused owned-cache operation', result.stderr)
            self.assertEqual(protected.read_bytes(), b'protected')
    def test_identity_swap_and_outside_manifest_are_refused(self):
        with tempfile.TemporaryDirectory(prefix='StillChromeProbe-') as temporary:
            root = pathlib.Path(temporary).resolve(); cache = root / 'Cache_Data'; cache.mkdir()
            leaf = cache / 'asset'; leaf.write_bytes(b'old'); s = leaf.stat()
            manifest = [{'path': str(leaf), 'dev': s.st_dev, 'ino': s.st_ino, 'size': s.st_size, 'mtimeMs': s.st_mtime_ns / 1000000}]
            replacement = cache / 'replacement'; replacement.write_bytes(b'new'); replacement.replace(leaf)
            result = subprocess.run(['python3', str(HELPER), str(root), str(cache)], input=json.dumps(manifest), text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0); self.assertIn('Refused owned-cache operation', result.stderr); self.assertEqual(leaf.read_bytes(), b'new')
            manifest[0]['path'] = str(root / 'Cookies')
            result = subprocess.run(['python3', str(HELPER), str(root), str(cache)], input=json.dumps(manifest), text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0); self.assertIn('Refused owned-cache operation', result.stderr)
if __name__ == '__main__': unittest.main()
