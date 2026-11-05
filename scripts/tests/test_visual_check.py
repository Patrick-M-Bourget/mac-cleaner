import importlib.util
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('visual_check', ROOT / 'scripts/visual-check.py')
visual_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(visual_check)


class CaptureArgumentTests(unittest.TestCase):
    def parse(self, *args):
        return visual_check.build_parser().parse_args(['capture', *args])

    def test_no_arguments_capture_overview_into_a_fresh_folder(self):
        args = self.parse()
        self.assertEqual(args.scenario, 'overview')
        self.assertIsNone(args.destination)

    def test_a_named_scenario_and_folder(self):
        args = self.parse('--scenario', 'audio-software', '/tmp/after')
        self.assertEqual(args.scenario, 'audio-software')
        self.assertEqual(args.destination, Path('/tmp/after'))

    def test_each_named_scenario_is_accepted(self):
        self.assertEqual(visual_check.SCENARIOS, ('overview', 'audio-software', 'photo-video'))
        for scenario in visual_check.SCENARIOS:
            with self.subTest(scenario=scenario):
                self.assertEqual(self.parse('--scenario', scenario).scenario, scenario)

    def test_an_unknown_scenario_is_refused_before_building(self):
        with self.assertRaises(SystemExit):
            self.parse('--scenario', 'nowhere')

    def test_every_scenario_is_one_the_capture_test_builds(self):
        source = (ROOT / 'CacheDrop/UITests/VisualCaptureUITests.swift').read_text()
        for scenario in visual_check.SCENARIOS:
            self.assertTrue(f'case "{scenario}"' in source, f'VisualCaptureUITests has no case "{scenario}"')


class OutputFolderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()

    def test_a_new_folder_outside_the_checkout_is_accepted(self):
        self.assertEqual(visual_check.output_folder(self.base / 'after'), self.base / 'after')

    def test_no_folder_means_a_fresh_one_later(self):
        self.assertIsNone(visual_check.output_folder(None))

    def test_a_reused_folder_is_refused_and_says_how_to_get_a_fresh_one(self):
        with self.assertRaisesRegex(ValueError, 'already exists.*leave out the folder'):
            visual_check.output_folder(self.base)

    def test_a_folder_inside_the_checkout_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'outside this checkout'):
            visual_check.output_folder(ROOT / '.build/new-captures')

    def capture(self):
        source = self.base / 'CacheDropVisual-run'
        source.mkdir()
        (source / 'manifest.json').write_text('{}')
        return source

    def test_without_a_folder_the_captures_land_in_a_fresh_temp_folder(self):
        source = self.capture()
        folder = visual_check.deliver(source, None, 'audio-software')
        self.addCleanup(shutil.rmtree, folder)
        self.assertTrue(folder.name.startswith('cachedrop-visual-audio-software-'))
        self.assertEqual(folder.parent, Path(tempfile.gettempdir()).resolve())
        self.assertTrue((folder / 'manifest.json').is_file())
        self.assertFalse(source.exists(), "The runner's copy is removed")
        again = visual_check.deliver(self.capture(), None, 'audio-software')
        self.addCleanup(shutil.rmtree, again)
        self.assertNotEqual(again, folder, 'Each run gets its own folder')

    def test_a_named_folder_receives_the_captures(self):
        folder = visual_check.deliver(self.capture(), self.base / 'before', 'overview')
        self.assertEqual(folder, self.base / 'before')
        self.assertTrue((folder / 'manifest.json').is_file())


class ScenarioPlanTests(unittest.TestCase):
    def test_the_ui_target_gets_the_capture_switch_and_scenario(self):
        plan = {'TestConfigurations': [{'TestTargets': [{'BlueprintName': 'CacheDropUITests', 'EnvironmentVariables': {'KEEP': '1'}}]}],
                '__xctestrun_metadata__': {'FormatVersion': 2}}
        modified = plistlib.loads(visual_check.capture_plan(plistlib.dumps(plan), 'audio-software'))
        environment = modified['TestConfigurations'][0]['TestTargets'][0]['EnvironmentVariables']
        self.assertEqual(environment, {'KEEP': '1', 'CACHEDROP_VISUAL_CAPTURE': '1', 'CACHEDROP_VISUAL_SCENARIO': 'audio-software'})

    def test_a_version_one_plan_is_read_too(self):
        plan = {'CacheDropUITests': {'BlueprintName': 'CacheDropUITests'}, 'CacheDropTests': {'BlueprintName': 'CacheDropTests'}}
        modified = plistlib.loads(visual_check.capture_plan(plistlib.dumps(plan), 'overview'))
        self.assertEqual(modified['CacheDropUITests']['EnvironmentVariables']['CACHEDROP_VISUAL_SCENARIO'], 'overview')
        self.assertNotIn('EnvironmentVariables', modified['CacheDropTests'])

    def test_a_plan_without_one_ui_target_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'exactly one UI test target'):
            visual_check.capture_plan(plistlib.dumps({'Other': {'BlueprintName': 'CacheDropTests'}}), 'overview')


class ManifestTests(unittest.TestCase):
    def test_the_pages_come_from_the_manifests(self):
        manifest = {name: {} for name in ('sounds-light.png', 'sounds-dark.png', 'drivers-light.png', 'drivers-dark.png')}
        self.assertEqual(visual_check.manifest_names([manifest, dict(manifest)]),
                         ['drivers-dark.png', 'drivers-light.png', 'sounds-dark.png', 'sounds-light.png'])

    def test_captures_of_different_scenarios_are_refused(self):
        overview = {'overview-light.png': {}, 'overview-dark.png': {}}
        sounds = {'sounds-light.png': {}, 'sounds-dark.png': {}}
        with self.assertRaisesRegex(ValueError, 'same pages'):
            visual_check.manifest_names([overview, sounds])

    def test_an_empty_manifest_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'same pages'):
            visual_check.manifest_names([{}, {}])


if __name__ == '__main__':
    unittest.main()
