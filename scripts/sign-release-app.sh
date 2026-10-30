#!/usr/bin/env bash
# Custom distribution signing, following Sparkle's documented inside-out order.
set -euo pipefail
verify=0
if [[ "${1:-}" == --verify ]]; then verify=1; shift; fi
[[ $# == 3 || ($# == 4 && ("$4" == --adhoc || "$4" == --signed)) ]] || { echo 'Usage: sign-release-app.sh [--verify] APP IDENTITY TEAM [--adhoc]' >&2; exit 2; }
app="$1"; identity="$2"; team="$3"
adhoc=0
[[ "${4:-}" != --adhoc ]] || adhoc=1
fail() { echo "sign-release-app: $*" >&2; exit 1; }
sparkle="$app/Contents/Frameworks/Sparkle.framework"
version="$sparkle/Versions/B"
# A changed layout must be audited rather than silently leaving ad-hoc nested code.
for code in "$version/XPCServices/Installer.xpc" "$version/XPCServices/Downloader.xpc" "$version/Autoupdate" "$version/Updater.app" "$sparkle"; do
  [[ -e "$code" ]] || fail "missing Sparkle code: ${code#"$app/"}"
done
timestamp=(--timestamp)
if ((adhoc)); then timestamp=(--timestamp=none); fi
sign() { codesign --force --sign "$identity" --options runtime "${timestamp[@]}" "$@"; }
if ((!verify)); then
  sign "$version/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$version/XPCServices/Downloader.xpc"
  sign "$version/Autoupdate"
  sign "$version/Updater.app"
  sign "$sparkle"
  # Other nested code remains inside-out; Sparkle was explicitly signed above.
  while IFS= read -r -d '' code; do
    sign "$code"
  done < <(find "$app/Contents" -depth \( -path "$sparkle" -o -path "$sparkle/*" \) -prune -o \
    \( -name '*.framework' -o -name '*.dylib' -o -name '*.bundle' -o -name '*.appex' -o -name '*.xpc' -o -name '*.app' -o -name '*.systemextension' \) -print0)
  sign "$app"
fi
# Check every nested Mach-O itself, not merely the outer bundle seal.
check() {
  local code="$1" details entitlements
  codesign --verify --strict --verbose=2 "$code"
  details="$(codesign -d --verbose=2 "$code" 2>&1)"
  [[ "$details" =~ flags=[^[:space:]]*runtime ]] || fail "Hardened Runtime is off: $code"
  if ((!adhoc)); then
    [[ "$details" == *"TeamIdentifier=$team"* && "$details" == *"Authority=Developer ID Application:"* ]] || fail "not a Developer ID signature from team $team: $code"
  fi
  entitlements="$(codesign -d --entitlements - --xml "$code" 2>/dev/null)"
  [[ "$entitlements" != *get-task-allow* ]] || fail "development entitlement: $code"
}
while IFS= read -r -d '' binary; do
  [[ "$(file -b "$binary")" != *Mach-O* ]] || check "$binary"
done < <(find "$app/Contents" -type f -print0)
check "$app"
codesign --verify --deep --strict --verbose=2 "$app"
