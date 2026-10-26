"""Public CLI refuses invalid standard qualification authority without mutation."""
import json
import os
import pathlib
import subprocess
import tempfile
import unittest

HELPER = pathlib.Path(__file__).with_name('cache-group.py')


class StandardProofBoundary(unittest.TestCase):
    def test_standard_mode_requires_real_hosted_context_and_never_uses_process_fixture(self):
        with tempfile.TemporaryDirectory(prefix='StillChromeProbe-') as temporary:
            root = pathlib.Path(temporary).resolve()
            cache = root / 'Default/Cache/Cache_Data'
            cache.mkdir(parents=True)
            leaf = cache / '0123456789abcdef_0'
            leaf.write_bytes(b'protected')
            proof = root / 'proof.json'
            proof.write_text('{}')
            fixture = root / 'process-fixture.json'
            fixture.write_text(json.dumps({'psOutput': '1 /sbin/launchd'}))
            env = dict(os.environ, GITHUB_ACTIONS='false', STILL_CHROME_PROBE_PROCESS_FIXTURE=str(fixture))
            result = subprocess.run(['python3', str(HELPER), str(root), str(cache),
                                     '/owned/Google Chrome.app', 'clean', '--standard-proof', str(proof)],
                                    input='{}', text=True, capture_output=True, env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('hosted standard proof required', result.stderr)
            self.assertEqual(leaf.read_bytes(), b'protected')

    def test_missing_forged_foreign_preexisting_or_unmatched_proofs_refuse_before_deletion(self):
        with tempfile.TemporaryDirectory(prefix='StillChromeProbe-') as temporary:
            root = pathlib.Path(temporary).resolve()
            cache = root / 'Default/Cache/Cache_Data'
            cache.mkdir(parents=True)
            leaf = cache / '0123456789abcdef_0'
            leaf.write_bytes(b'protected')
            proof = root / 'proof.json'
            env = dict(os.environ, GITHUB_ACTIONS='true', RUNNER_ENVIRONMENT='github-hosted',
                       RUNNER_OS='macOS', RUNNER_TEMP=str(root), GITHUB_RUN_ID='this-run', GITHUB_SHA='this-sha')
            env.pop('STILL_CHROME_PROBE_PROCESS_FIXTURE', None)
            base = {'schema': 1, 'githubRunID': 'this-run', 'githubSHA': 'this-sha',
                    'initialRootsAbsent': True, 'browserProfilePathMatched': True,
                    'result': 'passed mapping observation'}
            for label, body in [('missing', None), ('forged', {}),
                                ('foreign', dict(base, githubRunID='foreign-run')),
                                ('preexisting', dict(base, initialRootsAbsent=False)),
                                ('unmatched', dict(base, cacheGroup='/unexpected/group'))]:
                with self.subTest(proof=label):
                    if proof.exists(): proof.unlink()
                    if body is not None: proof.write_text(json.dumps(body))
                    result = subprocess.run(['python3', str(HELPER), str(root), str(cache),
                                             '/owned/Google Chrome.app', 'clean', '--standard-proof', str(proof)],
                                            input='{}', text=True, capture_output=True, env=env)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('standard proof', result.stderr)
                    self.assertEqual(leaf.read_bytes(), b'protected')


if __name__ == '__main__': unittest.main()
