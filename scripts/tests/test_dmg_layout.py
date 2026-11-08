import copy
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('dmg_layout', ROOT / 'scripts/dmg-layout.py')
dmg_layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dmg_layout)


class DiskImageLayoutTests(unittest.TestCase):
    def setUp(self):
        self.layout = dmg_layout.load()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.art = Path(self.temp.name)
        for name in ('background.png', 'background@2x.png'):
            shutil.copy(ROOT / 'scripts/dmg' / name, self.art / name)

    def test_the_committed_art_matches_the_layout_at_1x_and_2x(self):
        dmg_layout.check(self.layout, ROOT / 'scripts/dmg')

    def test_art_of_another_size_is_refused(self):
        shutil.copy(self.art / 'background@2x.png', self.art / 'background.png')
        with self.assertRaisesRegex(ValueError, 'background.png must be'):
            dmg_layout.check(self.layout, self.art)

    def test_an_icon_outside_the_window_is_refused(self):
        layout = copy.deepcopy(self.layout)
        layout['applications']['x'] = layout['window']['width'] - 10
        with self.assertRaisesRegex(ValueError, 'applications icon'):
            dmg_layout.check(layout, self.art)

    def test_icons_too_close_for_the_arrow_are_refused(self):
        layout = copy.deepcopy(self.layout)
        layout['applications']['x'] = layout['app']['x'] + layout['iconSize']
        with self.assertRaisesRegex(ValueError, 'arrow'):
            dmg_layout.check(layout, self.art)

    def test_the_script_places_both_items_and_sizes_the_window_with_its_title_bar(self):
        script = dmg_layout.applescript(self.layout, '/Volumes/CacheDrop')
        app, applications = self.layout['app'], self.layout['applications']
        left, top = dmg_layout.WINDOW_ORIGIN
        bottom = top + self.layout['window']['height'] + dmg_layout.TITLE_BAR
        self.assertIn(f'set bounds of container window to {{{left}, {top}, {left + self.layout["window"]["width"]}, {bottom}}}', script)
        self.assertIn(f'set position of item "CacheDrop.app" of container window to {{{app["x"]}, {app["y"]}}}', script)
        self.assertIn(f'set position of item "Applications" of container window to {{{applications["x"]}, {applications["y"]}}}', script)
        self.assertIn('set toolbar visible of container window to false', script)
        self.assertIn('set background picture of viewOptions to file ".background:background.tiff"', script)

    def test_the_mount_point_is_quoted_for_applescript(self):
        script = dmg_layout.applescript(self.layout, '/Volumes/Cache "Drop" \\ 1')
        self.assertIn('POSIX file "/Volumes/Cache \\"Drop\\" \\\\ 1" as alias', script)

    def test_release_lays_out_the_image_before_signing_notarizing_and_stapling_it(self):
        release = (ROOT / 'scripts/release.sh').read_text()
        make = release.index('scripts/make-dmg.sh"')
        self.assertLess(release.index('step "Notarizing the app"'), make)
        self.assertLess(make, release.index('step "Signing the DMG"'))
        self.assertLess(release.index('step "Signing the DMG"'), release.index('step "Notarizing the DMG"'))
        self.assertLess(release.index('notarize "$dmg"'), release.index('stapler staple "$dmg"'))


class MakeDiskImageTests(unittest.TestCase):
    """make-dmg.sh refuses while another CacheDrop volume is mounted: Finder names disks by volume name, so it would
    lay out that one instead of ours (#760)."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.volumes = self.root / 'Volumes'
        self.volumes.mkdir()
        (self.root / 'CacheDrop.app/Contents').mkdir(parents=True)

    def make(self):
        return subprocess.run(['bash', str(ROOT / 'scripts/make-dmg.sh'), str(self.root / 'CacheDrop.app'),
                               str(self.root / 'out.dmg')], env=dict(os.environ, CACHEDROP_DMG_VOLUMES=str(self.volumes)),
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)

    def test_a_mounted_cachedrop_volume_is_refused_up_front_by_its_mount_point(self):
        for name in ('CacheDrop', 'CacheDrop 1'):
            with self.subTest(name=name):
                volume = self.volumes / name
                volume.mkdir()
                result = self.make()
                volume.rmdir()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f'{volume} is already mounted', result.stdout)
                self.assertIn(f'hdiutil detach "{volume}"', result.stdout)
                self.assertFalse((self.root / 'out.dmg').exists())

    def test_the_layout_step_names_the_mount_point_it_checked(self):
        script = (ROOT / 'scripts/make-dmg.sh').read_text()
        self.assertIn('Finder wrote no window layout to $mount', script)


if __name__ == '__main__':
    unittest.main()
