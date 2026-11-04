#!/usr/bin/env bash
# Builds a release that is ready to publish, in one command, from origin/main after its version PR merged:
# a clean checkout at ../mac-cleaner-release-VERSION, the notes to sign, scripts/release.sh (signed, notarized,
# stapled, appcast), then the independent checks of docs/RELEASING.md. It uploads nothing. Publishing is
# cachedrop-website's scripts/publish-release.sh, run only when the owner says "publish" (website Decision 55).
set -euo pipefail

die() { echo "ship-release.sh: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

[[ $# -eq 1 && "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/ship-release.sh x.y.z"
version="$1"
# The production updates bucket: every release's immutable folder (docs/RELEASING.md).
artifact_base_url="https://dqpvfcthotskzfvdpjdm.supabase.co/storage/v1/object/public/updates/$version/"
team_id="8F5K2ZRP5T"

main_repo="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
checkout="$(dirname "$main_repo")/mac-cleaner-release-$version"

step "Checking origin/main"
git -C "$main_repo" fetch --quiet origin
commit="$(git -C "$main_repo" rev-parse origin/main)"
pbxproj="$(git -C "$main_repo" show origin/main:CacheDrop/CacheDrop.xcodeproj/project.pbxproj)"
grep -q "MARKETING_VERSION = $version;" <<<"$pbxproj" \
  || die "origin/main isn't $version yet: merge its version PR first (scripts/release.sh --bump $version)"
git -C "$main_repo" cat-file -e "origin/main:docs/releases/$version.html" 2>/dev/null \
  || die "origin/main has no docs/releases/$version.html"
echo "origin/main ${commit:0:12} is $version"

step "Clean checkout"
if [[ -d "$checkout" ]]; then
  [[ "$(git -C "$checkout" rev-parse HEAD)" == "$commit" ]] || die "$checkout exists at another commit; move it aside first"
  [[ -z "$(git -C "$checkout" status --porcelain)" ]] || die "$checkout has changes"
  echo "Reusing $checkout"
else
  git -C "$main_repo" worktree add --quiet --detach "$checkout" "$commit"
  echo "Created $checkout"
fi
cd "$checkout"

step "Release notes"
notes="$checkout/.build/release-notes/$version.html"
python3 scripts/release-notes.py "$version" --out "$notes"

scripts/release.sh --artifact-base-url "$artifact_base_url" --release-notes "$notes"

step "Independent verification"
out="$checkout/build/release" app="$out/CacheDrop.app" dmg="$out/CacheDrop-$version.dmg"
tools=""
for dir in "$checkout/.build/sparkle-tools/bin" "$main_repo/.build/sparkle-tools/bin"; do
  [[ -x "$dir/sign_update" ]] && { tools="$dir"; break; }
done
[[ -n "$tools" ]] || die "no Sparkle tools; see docs/RELEASING.md, Sparkle prerequisite setup"
scripts/sign-release-app.sh --verify "$app" - "$team_id"
spctl -a -t exec -vv "$app"
spctl -a -t open --context context:primary-signature -vv "$dmg"
for path in "$app" "$dmg"; do
  for attempt in 1 2 3; do xcrun stapler validate "$path" && break; ((attempt < 3)) || die "stapler validate $path failed"; sleep 20; done
done
python3 scripts/sparkle-release.py verify --app "$app" --dmg "$dmg" --tools "$tools" \
  --artifact-base-url "$artifact_base_url" --release-notes "$notes"

step "Ready to publish $version"
echo "Artifacts: $out"
echo "SHA-256:   $(shasum -a 256 "$dmg" | awk '{ print $1 }')"
echo "When the owner says \"publish\": cachedrop-website/scripts/publish-release.sh $out"
