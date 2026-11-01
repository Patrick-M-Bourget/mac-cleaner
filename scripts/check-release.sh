#!/bin/bash
# Build Release and reject Debug-only switches, gallery types and accessibility IDs in the shipped executable, and a
# license placeholder public key once gating is on (#594).
# --app PATH checks an existing app (also useful for proving a Debug build is rejected).
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [ "$#" -eq 0 ]; then
  xcodebuild build -project CacheDrop/CacheDrop.xcodeproj -scheme CacheDrop -configuration Release \
    -destination 'platform=macOS' -derivedDataPath .build/xcode
  app=.build/xcode/Build/Products/Release/CacheDrop.app
elif [ "$#" -eq 2 ] && [ "$1" = --app ]; then
  app=$2
else
  echo "Usage: scripts/check-release.sh [--app PATH]" >&2; exit 2
fi
[ -d "$app/Contents" ] || { echo "No app bundle: $app" >&2; exit 2; }
log=$(mktemp); trap 'rm -f "$log"' EXIT
count=0
# Xcode can put app code in a sibling .debug.dylib; embedded frameworks/helpers also ship with the app.
while IFS= read -r -d '' binary; do
  if ! /usr/bin/file -b "$binary" | grep -q 'Mach-O'; then continue; fi
  count=$((count + 1))
  xcrun nm -a "$binary" >>"$log"
  /usr/bin/strings -a "$binary" >>"$log"
done < <(find "$app/Contents" -type f -print0)
[ "$count" -gt 0 ] || { echo "No Mach-O binaries in $app" >&2; exit 2; }
if grep -E 'CACHEDROP_TEST_|DesignGallery|DebugGalleryCommands|designGallery|design-gallery|CapacityGalleryExamples|ButtonRuleGalleryExamples|ListHeaderGalleryExamples|ShellAppearanceGalleryExamples' "$log"; then
  echo "Debug-only code found in $app" >&2; exit 1
fi
# #594, Decision 136: once license gating is on (#595's single Swift condition LICENSE_GATING in the app's Release
# settings, read from this checkout), the app must carry the production public key, not the placeholder that rejects
# every key. LicensePublicKey.placeholder is the text looked for.
conditions=$(xcodebuild -showBuildSettings -project CacheDrop/CacheDrop.xcodeproj -target CacheDrop -configuration Release 2>/dev/null \
  | awk -F' = ' '$1 ~ /^ *SWIFT_ACTIVE_COMPILATION_CONDITIONS$/ { print $2 }') \
  || { echo "Couldn't read the Release build settings" >&2; exit 2; }
if [[ " $conditions " == *" LICENSE_GATING "* ]] && grep -q 'CacheDrop license public key placeholder' "$log"; then
  echo "License gating is on but $app still has the placeholder public key (docs/RELEASING.md, License keys)" >&2; exit 1
fi
echo "Release contains no test switches or gallery code ($count binaries checked)."
