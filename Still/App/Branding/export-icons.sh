#!/bin/zsh
# Re-exports AppIcon.appiconset from cachedrop-icon-light.svg (the source of truth).
# Needs Google Chrome (headless, for SVG filters) and Python 3 with Pillow. Run from anywhere:
#   Still/App/Branding/export-icons.sh
set -euo pipefail
here=${0:A:h}
set=$here/../Assets.xcassets/AppIcon.appiconset
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
tmp=$(mktemp -d); trap 'rm -rf $tmp' EXIT
print -r -- "<html><body style='margin:0;background:transparent'><img src='file://$here/cachedrop-icon-light.svg' width=1024 height=1024 style='display:block'></body></html>" > $tmp/page.html
"$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --window-size=1024,1024 \
  --default-background-color=00000000 --screenshot=$tmp/icon-1024.png file://$tmp/page.html >/dev/null 2>&1
python3 - "$tmp/icon-1024.png" "$set" <<'PY'
import sys
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGBA')
assert im.size == (1024, 1024) and all(im.getpixel(p)[3] == 0 for p in [(0, 0), (1023, 0), (0, 1023), (1023, 1023)]), "corners must be transparent"
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pt * scale
        im.resize((px, px), Image.LANCZOS).save(f"{out}/icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png", optimize=True)
PY
