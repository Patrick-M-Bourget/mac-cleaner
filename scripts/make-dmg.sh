#!/usr/bin/env bash
# Makes the unsigned disk image release.sh signs, notarizes and staples (#558): one fixed Finder window with the
# CacheDrop icon, an arrow and Applications on the background art, laid out by Finder from scripts/dmg/layout.json.
#
#   scripts/make-dmg.sh APP OUT.dmg
#
# Finder writes the window's .DS_Store while the writable image is mounted, so this needs a logged-in session and
# may ask once to let the terminal control Finder. The image is always detached, even on failure.
# Finder names disks by volume name, so it refuses while another CacheDrop volume is mounted (#760): Finder would lay
# out that one instead of ours. CACHEDROP_DMG_VOLUMES points the check at another folder for the tooling tests.
set -euo pipefail

die() { echo "make-dmg.sh: $*" >&2; exit 1; }
(( $# == 2 )) || die "usage: scripts/make-dmg.sh APP OUT.dmg"
app="$1"
dmg="$2"
[[ -d "$app/Contents" ]] || die "no app at $app"
scripts="$(cd "$(dirname "$0")" && pwd)"
art="$scripts/dmg"
python3 "$scripts/dmg-layout.py" check
volumes="${CACHEDROP_DMG_VOLUMES:-/Volumes}"
for other in "$volumes/CacheDrop" "$volumes/CacheDrop "[0-9]*; do
  [[ -e "$other" ]] && die "$other is already mounted and Finder would lay it out instead of ours; eject it with: hdiutil detach \"$other\""
done

work="$(mktemp -d "${TMPDIR:-/tmp}/cachedrop-dmg.XXXXXX")"
mount=""
cleanup() {
  if [[ -n "$mount" ]]; then
    hdiutil detach "$mount" -quiet || hdiutil detach "$mount" -force -quiet ||
      { echo "make-dmg.sh: could not detach $mount; retained $work" >&2; return; }
  fi
  rm -rf "$work"
}
trap cleanup EXIT

# The image's contents: the app, a link to /Applications and the art (in a hidden folder).
mkdir -p "$work/root/.background"
ditto "$app" "$work/root/CacheDrop.app"
ln -s /Applications "$work/root/Applications"
tiffutil -cathidpicheck "$art/background.png" "$art/background@2x.png" -out "$work/root/.background/background.tiff" 2>/dev/null

# A writable image to lay out, with room for Finder's .DS_Store.
hdiutil create -quiet -volname CacheDrop -srcfolder "$work/root" -fs HFS+ -format UDRW -size "$(( $(du -sm "$work/root" | cut -f1) + 20 ))m" "$work/rw.dmg"
mount="$(hdiutil attach -readwrite -noverify -noautoopen "$work/rw.dmg" | awk -F '\t' '/\/Volumes\// { print $NF; exit }')"
[[ -n "$mount" && -d "$mount/CacheDrop.app" ]] || die "could not mount the writable image"
[[ "$mount" == "$volumes/CacheDrop" ]] || die "the writable image mounted at $mount, not $volumes/CacheDrop; eject the other CacheDrop volume"

python3 "$scripts/dmg-layout.py" applescript "$mount" | osascript >/dev/null ||
  die "Finder could not lay out the disk image window (allow the terminal to control Finder in System Settings > Privacy & Security > Automation)"
for _ in {1..20}; do [[ -f "$mount/.DS_Store" ]] && break; sleep 0.25; done
[[ -f "$mount/.DS_Store" ]] || die "Finder wrote no window layout to $mount"
# The volume shows the app's icon. It goes in after Finder's layout, which removes an earlier .VolumeIcon.icns and
# its flag (and hdiutil create leaves one in -srcfolder out).
icon="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$app/Contents/Info.plist")"
cp "$app/Contents/Resources/${icon%.icns}.icns" "$mount/.VolumeIcon.icns"
SetFile -a C "$mount"
rm -rf "$mount/.fseventsd" "$mount/.Trashes"
sync
hdiutil detach "$mount" -quiet
mount=""

rm -f "$dmg"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg"
