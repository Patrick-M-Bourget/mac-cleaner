#!/usr/bin/env python3
"""Lays out the disk image's Finder window from scripts/dmg/layout.json (#558).

release.sh runs the printed AppleScript against the writable image while it is mounted, so Finder itself writes
the window's .DS_Store: one fixed window, no toolbar or sidebar, icon view, the background picture, and the app and
Applications placed where the art expects them. Nothing hand-made is committed.

    scripts/dmg-layout.py check                    # the layout and both background images agree
    scripts/dmg-layout.py applescript MOUNT_POINT  # print the Finder script for the mounted image
"""
import argparse
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = ROOT / 'scripts/dmg/layout.json'
# Where the window opens on screen, and the title bar Finder adds above the content (bounds include it).
WINDOW_ORIGIN = (200, 120)
TITLE_BAR = 28
BACKGROUND_FOLDER = '.background'
BACKGROUND_FILE = 'background.tiff'


def load(path: Path = LAYOUT) -> dict:
    return json.loads(path.read_text())


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise ValueError(f'{path.name} is not a PNG')
    return struct.unpack('>II', data[16:24])


def check(layout: dict, art: Path) -> None:
    """Raises ValueError unless both icons sit inside the window, apart, and the 1x and 2x art match the window."""
    width, height, half = layout['window']['width'], layout['window']['height'], layout['iconSize'] / 2
    for key in ('app', 'applications'):
        item = layout[key]
        if not (half <= item['x'] <= width - half and half <= item['y'] <= height - half - layout['textSize'] * 2):
            raise ValueError(f'the {key} icon and its name must fit inside the {width}×{height} window')
    if layout['applications']['x'] - layout['app']['x'] < layout['iconSize'] * 2:
        raise ValueError('the app and Applications need at least two icon widths between their centres for the arrow')
    if layout['app']['name'] != 'CacheDrop.app' or layout['applications']['name'] != 'Applications':
        raise ValueError('the layout must place CacheDrop.app and Applications, the two items release.sh puts on the image')
    for name, scale in (('background.png', 1), ('background@2x.png', 2)):
        if png_size(art / name) != (width * scale, height * scale):
            raise ValueError(f'{name} must be {width * scale}×{height * scale}; '
                             'regenerate it with scripts/dmg/background.swift')


def quoted(text: str) -> str:
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def applescript(layout: dict, mount_point: str) -> str:
    """The Finder script for the image mounted at mount_point. Finder still resolves the disk by volume name, so a
    second "CacheDrop" volume would receive the layout; make-dmg.sh refuses while one is mounted (#760)."""
    left, top = WINDOW_ORIGIN
    right, bottom = left + layout['window']['width'], top + layout['window']['height'] + TITLE_BAR
    app, applications = layout['app'], layout['applications']
    return f'''tell application "Finder"
  -- Finder can take a moment to see a volume hdiutil has just mounted.
  repeat 40 times
    try
      set theDisk to disk of (POSIX file {quoted(mount_point)} as alias)
      exit repeat
    on error
      delay 0.25
    end try
  end repeat
  tell theDisk
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {{{left}, {top}, {right}, {bottom}}}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to {layout['iconSize']}
    set text size of viewOptions to {layout['textSize']}
    set label position of viewOptions to bottom
    set shows item info of viewOptions to false
    set shows icon preview of viewOptions to false
    set background picture of viewOptions to file {quoted(BACKGROUND_FOLDER + ':' + BACKGROUND_FILE)}
    set position of item {quoted(app['name'])} of container window to {{{app['x']}, {app['y']}}}
    set position of item {quoted(applications['name'])} of container window to {{{applications['x']}, {applications['y']}}}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('check')
    script = commands.add_parser('applescript')
    script.add_argument('mount_point')
    args = parser.parse_args()
    layout = load()
    try:
        check(layout, LAYOUT.parent)
    except ValueError as error:
        print(f'dmg-layout.py: {error}', file=sys.stderr)
        return 1
    if args.command == 'applescript':
        sys.stdout.write(applescript(layout, args.mount_point))
    return 0


if __name__ == '__main__':
    sys.exit(main())
