"""#520: checklist CLI with temporary repos and operator-supplied artifacts."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[1] / 'updater-acceptance.py'


class AcceptanceChecklistTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git('init', '-q')
        (self.repo / 'source').write_text('fixture source')
        self.git('add', 'source')
        self.commit()
        self.artifact = self.repo / 'update.dmg'
        self.artifact.write_bytes(b'operator artifact')
        self.inputs = self.repo / 'artifacts.json'
        self.inputs.write_text(json.dumps([dict(identity='B 0.9.5 (6)', path='update.dmg',
            sha256=hashlib.sha256(self.artifact.read_bytes()).hexdigest(), mode='Release')]))

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.repo, capture_output=True, text=True, check=True)

    def commit(self):
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Source')

    def cli(self, *args):
        return subprocess.run([sys.executable, str(CLI), *args], cwd=self.repo, capture_output=True, text=True)

    def initialize(self):
        return self.cli('init', '--run', 'check', '--artifacts', str(self.inputs))

    def test_run_starts_pending_and_resumes_recorded_observations(self):
        result = self.initialize()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        status = self.cli('status', '--run', 'check')
        self.assertEqual(status.returncode, 1)
        self.assertIn('pending full-disk-access', status.stdout)
        self.assertIn('pending relaunch', status.stdout)
        recorded = self.cli('record', '--run', 'check', '--case', 'manual-checks', '--result', 'pass',
                            '--artifact', 'B 0.9.5 (6)', '--note', 'Menu and Settings checks worked')
        self.assertEqual(recorded.returncode, 0, recorded.stdout + recorded.stderr)
        resumed = self.cli('status', '--run', 'check')
        self.assertEqual(resumed.returncode, 1)
        self.assertIn('pass manual-checks', resumed.stdout)
        self.assertNotIn('pending manual-checks', resumed.stdout)
        self.assertIn('Release', resumed.stdout)
        self.assertIn('Menu and Settings checks worked', resumed.stdout)

    def test_completion_requires_every_case_and_a_failed_case_can_be_retried(self):
        self.assertEqual(self.initialize().returncode, 0)
        manifest = self.repo / '.build/updater-acceptance/check/run.json'
        cases = list(json.loads(manifest.read_text())['cases'])
        for name in cases:
            result = self.cli('record', '--run', 'check', '--case', name, '--result', 'fail' if name == cases[-1] else 'pass',
                              '--artifact', 'B 0.9.5 (6)', '--note', 'Explicit observed result')
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.cli('status', '--run', 'check').returncode, 1)
        self.cli('record', '--run', 'check', '--case', cases[-1], '--result', 'pass',
                 '--artifact', 'B 0.9.5 (6)', '--note', 'Retried successfully')
        self.assertEqual(self.cli('status', '--run', 'check').returncode, 0)

    def test_changed_source_or_artifact_refuses_reuse_without_overwriting_results(self):
        self.assertEqual(self.initialize().returncode, 0)
        manifest = self.repo / '.build/updater-acceptance/check/run.json'
        before = manifest.read_bytes()
        self.assertEqual(self.initialize().returncode, 2)
        self.assertEqual(manifest.read_bytes(), before)
        self.artifact.write_bytes(b'changed artifact')
        self.assertEqual(self.cli('status', '--run', 'check').returncode, 2)
        self.artifact.write_bytes(b'operator artifact')
        (self.repo / 'source').write_text('changed source')
        self.git('add', 'source')
        self.commit()
        stale = self.cli('record', '--run', 'check', '--case', 'manual-checks', '--result', 'pass',
                         '--artifact', 'B 0.9.5 (6)', '--note', 'Cannot reuse old run')
        self.assertEqual(stale.returncode, 2)
        self.assertIn('source changed', stale.stderr)
        self.assertEqual(manifest.read_bytes(), before)

    def test_fixture_and_release_observations_remain_distinct(self):
        entries = json.loads(self.inputs.read_text())
        entries.append(dict(entries[0], identity='Debug fixture B', mode='fixture'))
        self.inputs.write_text(json.dumps(entries))
        self.assertEqual(self.initialize().returncode, 0)
        result = self.cli('record', '--run', 'check', '--case', 'maintenance', '--result', 'pass',
                          '--artifact', 'Debug fixture B', '--note', 'Held a fixture write')
        self.assertEqual(result.returncode, 0)
        status = self.cli('status', '--run', 'check')
        self.assertIn('Debug fixture B [fixture]', status.stdout)
        self.assertNotIn('Debug fixture B [Release]', status.stdout)

    def test_bad_hash_unknown_identity_and_blank_observation_are_refused(self):
        self.artifact.write_bytes(b'wrong bytes')
        self.assertEqual(self.initialize().returncode, 2)
        self.artifact.write_bytes(b'operator artifact')
        self.assertEqual(self.initialize().returncode, 0)
        for identity, note in [('unknown artifact', 'Observed'), ('B 0.9.5 (6)', ' ')]:
            self.assertEqual(self.cli('record', '--run', 'check', '--case', 'manual-checks', '--result', 'pass',
                                     '--artifact', identity, '--note', note).returncode, 2)


if __name__ == '__main__':
    unittest.main()
