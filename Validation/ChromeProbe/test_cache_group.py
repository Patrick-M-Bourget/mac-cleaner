"""Public disposable group CLI: group approval may include later cache entries."""
import json, os, pathlib, select, subprocess, tempfile, unittest
HELPER = pathlib.Path(__file__).with_name('cache-group.py')
class CacheGroupBoundary(unittest.TestCase):
    def test_later_group_entries_removed_and_protected_sibling_preserved(self):
        with tempfile.TemporaryDirectory(prefix='StillChromeProbe-') as temporary:
            root = pathlib.Path(temporary).resolve(); fixture = root/'process-fixture.json'; fixture.write_text(json.dumps({'psOutput':'1 /sbin/launchd'})); env = dict(os.environ, STILL_CHROME_PROBE_PROCESS_FIXTURE=str(fixture)); cache = root/'Default'/'Cache'/'Cache_Data'; cache.mkdir(parents=True)
            (cache/'0123456789abcdef_0').write_bytes(b'cache'); protected = root/'Default'/'Cookies'; protected.write_bytes(b'protected')
            args = ['python3', str(HELPER), str(root), str(cache), '/nonexistent/Google Chrome.app']
            observed = subprocess.run(args+['observe'], text=True, capture_output=True, env=env)
            self.assertEqual(observed.returncode, 0, observed.stderr)
            (cache/'fedcba9876543210_0').write_bytes(b'new')
            result = subprocess.run(args+['clean'], input=observed.stdout, text=True, capture_output=True, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)['removed'], 2)
            self.assertEqual(list(cache.iterdir()), []); self.assertEqual(protected.read_bytes(), b'protected')
    def test_replaced_directory_and_symlink_are_refused_without_changing_protected_data(self):
        for replacement in ('directory', 'symlink'):
            with self.subTest(replacement=replacement), tempfile.TemporaryDirectory(prefix='StillChromeProbe-') as temporary:
                root = pathlib.Path(temporary).resolve(); fixture = root/'process-fixture.json'; fixture.write_text(json.dumps({'psOutput':'1 /sbin/launchd'})); env = dict(os.environ, STILL_CHROME_PROBE_PROCESS_FIXTURE=str(fixture)); cache = root/'Default'/'Cache'/'Cache_Data'; cache.mkdir(parents=True)
                leaf = cache/'0123456789abcdef_0'; leaf.write_bytes(b'cache')
                args = ['python3', str(HELPER), str(root), str(cache), '/nonexistent/Google Chrome.app']
                observed = subprocess.run(args+['observe'], text=True, capture_output=True, env=env); self.assertEqual(observed.returncode, 0)
                cache.rename(cache.with_name('prior'))
                if replacement == 'directory': cache.mkdir(); (cache/'0123456789abcdef_0').write_bytes(b'protected')
                else: cache.symlink_to(cache.with_name('prior'), target_is_directory=True)
                result = subprocess.run(args+['clean'], input=observed.stdout, text=True, capture_output=True, env=env)
                self.assertNotEqual(result.returncode, 0); self.assertIn('Refused group operation', result.stderr)
                self.assertEqual((cache.with_name('prior')/'0123456789abcdef_0').read_bytes(), b'cache')
                if replacement == 'directory': self.assertEqual((cache/'0123456789abcdef_0').read_bytes(), b'protected')
    def test_new_helper_activity_stops_unstarted_work_and_reports_partial_count(self):
        with tempfile.TemporaryDirectory(prefix='StillChromeProbe-') as temporary:
            root = pathlib.Path(temporary).resolve(); cache = root/'Default'/'Cache'/'Cache_Data'; cache.mkdir(parents=True)
            for name in ('0123456789abcdef_0', 'fedcba9876543210_0'): (cache/name).write_bytes(b'cache')
            fixture = root/'process-fixture.json'; fixture.write_text(json.dumps({'psOutput':'1 /sbin/launchd'}))
            env = dict(os.environ, STILL_CHROME_PROBE_PROCESS_FIXTURE=str(fixture))
            args = ['python3', str(HELPER), str(root), str(cache), '/owned/Google Chrome.app']
            observed = subprocess.run(args+['observe'], text=True, capture_output=True, env=env); self.assertEqual(observed.returncode, 0)
            fixture.write_text(json.dumps({'psOutput':['1 /sbin/launchd', '1 /sbin/launchd', '999999 /owned/Google Chrome.app/Contents/Frameworks/Helper']}))
            result = subprocess.run(args+['clean'], input=observed.stdout, text=True, capture_output=True, env=env)
            self.assertNotEqual(result.returncode, 0); outcome = json.loads(result.stdout)
            self.assertEqual(outcome['removed'], 1); self.assertEqual(outcome['status'], 'stopped')
            self.assertIn('activity observed', outcome['reason']); self.assertEqual(len(list(cache.iterdir())), 1)
    def test_observed_index_swap_stops_after_first_leaf_and_preserves_both_indexes(self):
        with tempfile.TemporaryDirectory(prefix='StillChromeProbe-') as temporary:
            root = pathlib.Path(temporary).resolve(); cache = root/'Default/Cache/Cache_Data'; cache.mkdir(parents=True)
            (cache/'0123456789abcdef_0').write_bytes(b'cache'); index = cache/'index-dir'; index.mkdir(); (index/'the-real-index').write_bytes(b'original')
            fixture = root/'process-fixture.json'; fixture.write_text(json.dumps({'psOutput':'1 /sbin/launchd'}))
            env = dict(os.environ, STILL_CHROME_PROBE_PROCESS_FIXTURE=str(fixture)); args = ['python3', str(HELPER), str(root), str(cache), '/owned/Google Chrome.app']
            observed = subprocess.run(args+['observe'], text=True, capture_output=True, env=env)
            process = subprocess.Popen(args+['clean','--progress','--pace-ms','1000'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
            process.stdin.write(observed.stdout); process.stdin.close(); process.stdin = None
            self.assertTrue(select.select([process.stderr], [], [], 5)[0]); self.assertEqual(json.loads(process.stderr.readline())['count'], 1)
            index.rename(cache/'original-index'); index.mkdir(); (index/'the-real-index').write_bytes(b'replacement')
            stdout, stderr = process.communicate(timeout=5); result = json.loads(stdout)
            self.assertNotEqual(process.returncode, 0); self.assertEqual(result['removed'], 1); self.assertIn('index directory changed', result['reason'])
            self.assertEqual((cache/'original-index/the-real-index').read_bytes(), b'original'); self.assertEqual((index/'the-real-index').read_bytes(), b'replacement')
    @unittest.skipIf(os.getuid() == 0, 'root bypasses mode denial')
    def test_actual_directory_mode_denial_preserves_target(self):
        with tempfile.TemporaryDirectory(prefix='StillChromeProbe-') as temporary:
            root = pathlib.Path(temporary).resolve(); cache = root/'Default/Cache/Cache_Data'; cache.mkdir(parents=True)
            leaf = cache/'0123456789abcdef_0'; leaf.write_bytes(b'cache')
            fixture = root/'process-fixture.json'; fixture.write_text(json.dumps({'psOutput':'1 /sbin/launchd'}))
            env = dict(os.environ, STILL_CHROME_PROBE_PROCESS_FIXTURE=str(fixture)); args = ['python3', str(HELPER), str(root), str(cache), '/owned/Google Chrome.app']
            observed = subprocess.run(args+['observe'], text=True, capture_output=True, env=env); cache.chmod(0o500)
            try:
                result = subprocess.run(args+['clean'], input=observed.stdout, text=True, capture_output=True, env=env)
                self.assertNotEqual(result.returncode, 0); self.assertEqual(json.loads(result.stdout)['removed'], 0); self.assertIn('Permission denied', result.stdout); self.assertEqual(leaf.read_bytes(), b'cache')
            finally: cache.chmod(0o700)
    def test_progress_reports_completed_work_before_next_target(self):
        with tempfile.TemporaryDirectory(prefix='StillChromeProbe-') as temporary:
            root = pathlib.Path(temporary).resolve(); cache = root/'Default'/'Cache'/'Cache_Data'; cache.mkdir(parents=True)
            (cache/'0123456789abcdef_0').write_bytes(b'cache')
            fixture = root/'process-fixture.json'; fixture.write_text(json.dumps({'psOutput':'1 /sbin/launchd'}))
            env = dict(os.environ, STILL_CHROME_PROBE_PROCESS_FIXTURE=str(fixture))
            args = ['python3', str(HELPER), str(root), str(cache), '/owned/Google Chrome.app']
            observed = subprocess.run(args+['observe'], text=True, capture_output=True, env=env)
            result = subprocess.run(args+['clean', '--progress', '--pace-ms', '1'], input=observed.stdout, text=True, capture_output=True, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stderr), {'event':'removed', 'count':1})
    def test_unknown_process_observation_refuses_without_mutation(self):
        with tempfile.TemporaryDirectory(prefix='StillChromeProbe-') as temporary:
            root = pathlib.Path(temporary).resolve(); cache = root/'Default'/'Cache'/'Cache_Data'; cache.mkdir(parents=True)
            leaf = cache/'0123456789abcdef_0'; leaf.write_bytes(b'cache')
            fixture = root/'process-fixture.json'; env = dict(os.environ, STILL_CHROME_PROBE_PROCESS_FIXTURE=str(fixture))
            args = ['python3', str(HELPER), str(root), str(cache), '/owned/Google Chrome.app']
            fixture.write_text(json.dumps({'psOutput':'1 /sbin/launchd'}))
            observed = subprocess.run(args+['observe'], text=True, capture_output=True, env=env); self.assertEqual(observed.returncode, 0)
            for observation in ('', '1234', 'not-a-pid /unknown', None):
                with self.subTest(observation=observation):
                    fixture.write_text(json.dumps({'psOutput':observation}))
                    result = subprocess.run(args+['clean'], input=observed.stdout, text=True, capture_output=True, env=env)
                    self.assertNotEqual(result.returncode, 0, 'unknown observation must not authorize cleanup')
                    self.assertEqual(leaf.read_bytes(), b'cache')
if __name__ == '__main__': unittest.main()
