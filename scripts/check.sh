#!/bin/bash
# Runs what CI runs, on this Mac: the source checks, the Core suite (normal, then strict pool with the pool guard alone,
# #242), StorageAlerts' suite and the app build. Run it before every commit; UI journeys are separate
# (scripts/ui-journeys.sh). Prints one line per step and the output of any that fail.
#
#   scripts/check.sh            everything
#   scripts/check.sh --fast     the source checks and the Core suite only
set -uo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fast=0; [ "${1:-}" = "--fast" ] && fast=1
guard=aRunningToolLeavesTheConcurrencyPoolFree
log=$(mktemp); trap 'rm -f "$log"' EXIT
failed=0

step() {
  local name=$1; shift
  if "$@" >"$log" 2>&1; then echo "ok    $name"; else echo "FAIL  $name"; tail -40 "$log" | cut -c1-300; failed=1; fi
}

step "debug seams" scripts/check-debug-seams.sh
step "decision numbers" scripts/check-decisions.sh
step "copy terms" scripts/check-copy.sh
step "stored keys" scripts/check-stored-keys.sh
step "Core tests" swift test --package-path Packages/CacheDropCore
if [ "$fast" -eq 0 ]; then
  step "Core tests, strict pool" env LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 swift test --package-path Packages/CacheDropCore --skip "$guard"
  step "pool guard, strict pool, alone" env LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 swift test --package-path Packages/CacheDropCore --filter "$guard"
  step "StorageAlerts tests" swift test --package-path CacheDrop/Packages/StorageAlerts
  step "app build" xcodebuild build -project CacheDrop/CacheDrop.xcodeproj -scheme CacheDrop -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode
fi
exit $failed
