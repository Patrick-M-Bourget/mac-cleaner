#!/usr/bin/env bash
# Builds, signs, notarizes and staples the CacheDrop DMG (#315). Run with --help for usage.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release.sh [--adhoc] [--team-id ID] [--notary-profile NAME]
                         [--sparkle-tools DIR] [--artifact-base-url HTTPS_URL]
                         [--release-notes REVIEWED.html] [--keychain-account NAME]
       scripts/release.sh --bump <x.y.z>

Builds CacheDrop Release from a clean export of HEAD, signs it with the
Developer ID, makes build/release/CacheDrop-<version>.dmg, notarizes and
staples the app and the DMG, verifies them, and prints the architecture,
version, minimum macOS and SHA-256.

Options:
  --bump <x.y.z>         Prepare an explicit increasing stable version and the
                         next build number, then stop. Review and commit the
                         edits before running the separate clean-HEAD release.
  --adhoc                Sign ad hoc and skip notarization, stapling and the
                         Gatekeeper checks. Checks the build without contacting
                         Apple. Writes CacheDrop-<version>-adhoc.dmg.
  --team-id ID           Developer ID team. Env CACHEDROP_TEAM_ID.
                         Default 8F5K2ZRP5T.
  --notary-profile NAME  notarytool keychain profile (see
                         `xcrun notarytool store-credentials`).
                         Env CACHEDROP_NOTARY_PROFILE. Default cachedrop-notary.
  --sparkle-tools DIR   Sparkle 2.10.1 bin directory; CACHEDROP_SPARKLE_TOOLS.
  --artifact-base-url URL  Immutable HTTPS directory for this version's DMG.
                         CACHEDROP_ARTIFACT_BASE_URL. Required for signed mode.
  --release-notes FILE   Reviewed HTML fragment embedded in the local appcast.
                         Required for signed mode. No upload or publication.
  --keychain-account NAME  Sparkle Keychain account; default ed25519. Private
                         keys are never accepted as files or environment values.
  -h, --help             Show this help.

The working tree must be clean: the build is of HEAD, not of local edits.
The signed mode submits to Apple's notary service twice: the app (so the copy
inside the DMG carries its own stapled ticket), then the DMG.
EOF
}

die() { echo "release.sh: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

if [[ "${1:-}" == --bump ]]; then
  (( $# == 2 )) || die "--bump needs exactly one stable x.y.z version"
  exec python3 "$(dirname "$0")/prepare-version.py" "$2"
fi

adhoc=0
team_id="${CACHEDROP_TEAM_ID:-8F5K2ZRP5T}"
notary_profile="${CACHEDROP_NOTARY_PROFILE:-cachedrop-notary}"
sparkle_tools="${CACHEDROP_SPARKLE_TOOLS:-}"
artifact_base_url="${CACHEDROP_ARTIFACT_BASE_URL:-}"
release_notes=""
keychain_account="ed25519"
while (($#)); do
  case "$1" in
    --adhoc) adhoc=1 ;;
    --team-id) (($# > 1)) || die "--team-id needs a value"; team_id="$2"; shift ;;
    --notary-profile) (($# > 1)) || die "--notary-profile needs a value"; notary_profile="$2"; shift ;;
    --sparkle-tools) (($# > 1)) || die "--sparkle-tools needs a bin directory"; sparkle_tools="$2"; shift ;;
    --artifact-base-url) (($# > 1)) || die "--artifact-base-url needs an HTTPS directory"; artifact_base_url="$2"; shift ;;
    --release-notes) (($# > 1)) || die "--release-notes needs a reviewed HTML file"; release_notes="$2"; shift ;;
    --keychain-account) (($# > 1)) || die "--keychain-account needs an account"; keychain_account="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done

# xcode-select may point at the Command Line Tools, which can't build the app.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

repo="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
out_dir="$repo/build/release"
[[ "$team_id" == 8F5K2ZRP5T ]] || die "the distribution team must remain 8F5K2ZRP5T"

# 1. Clean working tree.
step "Checking the working tree"
[[ -z "$(git -C "$repo" status --porcelain)" ]] || die "the working tree has changes; commit or stash them first"
source_commit="$(git -C "$repo" rev-parse HEAD)"
commit="${source_commit:0:12}"
echo "Building $commit"

identity="-"
if ((!adhoc)); then
  [[ -n "$sparkle_tools" && -n "$artifact_base_url" && -n "$release_notes" ]] || die "signed releases require --sparkle-tools, --artifact-base-url and --release-notes (see docs/RELEASING.md)"
  python3 "$repo/scripts/sparkle-release.py" preflight --plist "$repo/CacheDrop/UpdateInfo.plist" \
    --tools "$sparkle_tools" --artifact-base-url "$artifact_base_url" --release-notes "$release_notes" --account "$keychain_account"
  # The identity's SHA-1, so a second certificate with the same name can't make codesign ambiguous.
  identity="$(security find-identity -v -p codesigning | awk -v team="($team_id)\"" \
    '/"Developer ID Application: / && index($0, team) && !n++ { print $2 }')"
  [[ -n "$identity" ]] || die "no valid 'Developer ID Application' identity for team $team_id in the keychain"
  echo "Signing identity: $(security find-identity -v -p codesigning | awk -v h="$identity" '$2 == h && !n++ { sub(/^[^"]*/, ""); print }')"
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/cachedrop-release.XXXXXX")"
dmg_mount=""
cleanup() {
  if [[ -n "$dmg_mount" ]]; then
    hdiutil detach "$dmg_mount" -quiet || { echo "release.sh: could not detach verification DMG; retained $work" >&2; return; }
  fi
  rm -rf "$work"
}
trap cleanup EXIT

# 2. Release build from an export of HEAD.
step "Building Release"
mkdir "$work/src"
git -C "$repo" archive "$source_commit" | tar -x -C "$work/src"
if ! xcodebuild build -project "$work/src/CacheDrop/CacheDrop.xcodeproj" -scheme CacheDrop -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$work/dd" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO >"$work/build.log" 2>&1; then
  grep -E 'error:' "$work/build.log" >&2 || tail -40 "$work/build.log" >&2
  die "the Release build failed"
fi
built="$work/dd/Build/Products/Release/CacheDrop.app"
[[ -d "$built" ]] || die "no CacheDrop.app in the build products"

plist="$built/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
min_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")"
exe="$built/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"

# 3. Sign each Sparkle helper explicitly, then the framework and outer app.
step "Signing and verifying every nested executable"
timestamp=(--timestamp)
sign_mode=(--signed)
if ((adhoc)); then timestamp=(--timestamp=none); sign_mode=(--adhoc); fi
"$repo/scripts/sign-release-app.sh" "$built" "$identity" "$team_id" "${sign_mode[@]}"

notarize() { # path
  local result status id
  result="$(xcrun notarytool submit "$1" --keychain-profile "$notary_profile" --wait --output-format json)" || true
  status="$(plutil -extract status raw -o - - <<<"$result" 2>/dev/null || true)"
  id="$(plutil -extract id raw -o - - <<<"$result" 2>/dev/null || true)"
  echo "notarytool: ${status:-no status} ${id:+(submission $id)}"
  if [[ "$status" != Accepted ]]; then
    echo "$result" >&2
    [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$notary_profile" >&2
    die "notarization of $(basename "$1") failed"
  fi
}

if ((!adhoc)); then
  # The app is notarized on its own first, so the copy in the DMG carries a stapled
  # ticket and opens offline once copied out of the DMG.
  step "Notarizing the app"
  ditto -c -k --keepParent "$built" "$work/CacheDrop.zip"
  notarize "$work/CacheDrop.zip"
  xcrun stapler staple "$built"
fi

# 4. DMG: the app and a link to /Applications.
step "Making the DMG"
mkdir -p "$out_dir"
# An if, not $( ((adhoc)) && … ): under set -e a failing substitution in an assignment ends the script.
suffix=""
if ((adhoc)); then suffix="-adhoc"; fi
dmg_name="CacheDrop-$version$suffix.dmg"
dmg="$out_dir/$dmg_name"
mkdir "$work/dmg"
ditto "$built" "$work/dmg/CacheDrop.app"
ln -s /Applications "$work/dmg/Applications"
# Invalidate old local success metadata before replacing any artifact bytes.
rm -f "$out_dir/appcast.xml" "$out_dir/release-identity.json"
rm -f "$dmg"
hdiutil create -quiet -volname CacheDrop -srcfolder "$work/dmg" -fs HFS+ -format UDZO -ov "$dmg"

# 5. Sign the DMG.
step "Signing the DMG"
codesign --force --sign "$identity" "${timestamp[@]}" "$dmg"
codesign --verify --strict --verbose=2 "$dmg"

# 6-7. Notarize and staple the DMG.
if ((!adhoc)); then
  step "Notarizing the DMG"
  notarize "$dmg"
  xcrun stapler staple "$dmg"
fi

# Keep the app next to the DMG for a launch check.
rm -rf "$out_dir/CacheDrop.app"
ditto "$built" "$out_dir/CacheDrop.app"
app="$out_dir/CacheDrop.app"

# 8. Verify.
step "Verifying"
"$repo/scripts/sign-release-app.sh" --verify "$app" "$identity" "$team_id" "${sign_mode[@]}"
if ((adhoc)); then
  echo "Skipped (ad hoc): spctl and stapler validate"
else
  spctl -a -t exec -vv "$app"
  spctl -a -t open --context context:primary-signature -vv "$dmg"
  xcrun stapler validate "$app"
  xcrun stapler validate "$dmg"
fi
# Verify the app actually carried by the final disk image, mounted read-only.
mkdir "$work/verify-dmg"
dmg_mount="$work/verify-dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$dmg_mount" "$dmg" >/dev/null
"$repo/scripts/sign-release-app.sh" --verify "$dmg_mount/CacheDrop.app" "$identity" "$team_id" "${sign_mode[@]}"
if ((!adhoc)); then xcrun stapler validate "$dmg_mount/CacheDrop.app"; fi
hdiutil detach "$dmg_mount" -quiet
dmg_mount=""

# 9. No DEBUG test seams in the Release binaries.
step "Checking for test seams"
seams=0
while IFS= read -r -d '' file; do
  [[ "$(file -b "$file")" == *Mach-O* ]] || continue
  if grep -aq 'CACHEDROP_TEST_' "$file"; then echo "CACHEDROP_TEST_ string in ${file#"$app/"}" >&2; seams=1; fi
  if [[ "$(nm -a "$file" 2>/dev/null || true)" == *thisMac* ]] || grep -aq 'thisMac' "$file"; then
    echo "thisMac symbol in ${file#"$app/"}" >&2; seams=1
  fi
done < <(find "$app/Contents" -type f -perm -u+x -print0)
((seams == 0)) || die "the Release build contains DEBUG test seams"
echo "No CACHEDROP_TEST_ strings or thisMac symbols"

# 10. EdDSA-sign only after both app and DMG have been notarized and stapled.
# The generator validates exact final bytes and metadata; no later command mutates the DMG.
if ((!adhoc)); then
  step "Generating and verifying the local Sparkle appcast"
  python3 "$repo/scripts/sparkle-release.py" generate --app "$app" --dmg "$dmg" --tools "$sparkle_tools" \
    --artifact-base-url "$artifact_base_url" --release-notes "$release_notes" --account "$keychain_account" \
    --commit "$source_commit"
fi

# 11. Summary.
step "Done"
binary_min_os="$(vtool -show-build "$app/Contents/MacOS/$(basename "$exe")" 2>/dev/null | awk '/minos/ && !n++ { print $2 }')"
echo "Mode:         $( ((adhoc)) && echo "ad hoc (not notarized, not for distribution)" || echo "Developer ID, notarized, stapled")"
echo "Commit:       $commit"
echo "Architecture: $(lipo -archs "$app/Contents/MacOS/$(basename "$exe")")"
echo "Version:      $version ($build_number)"
echo "Minimum OS:   macOS $min_os (binary minos ${binary_min_os:-unknown})"
echo "App:          $app"
echo "DMG:          $dmg"
echo "SHA-256:      $(shasum -a 256 "$dmg" | awk '{ print $1 }')"
