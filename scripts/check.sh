#!/bin/bash
# Runs what CI runs, on this Mac: the source checks, the Core suite (normal, then strict pool with the pool guard alone,
# #242), StorageAlerts' suite and Debug/Release app builds. Run it before every commit; UI journeys are separate
# (scripts/ui-journeys.sh). Failed steps retain full logs in .build/check-logs; successful logs are removed.
#
#   scripts/check.sh            everything
#   scripts/check.sh --fast     the source checks and the Core suite only
set -uo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fast=0; [ "${1:-}" = "--fast" ] && fast=1
guard=aRunningToolLeavesTheConcurrencyPoolFree
mkdir -p .build/check-logs || exit 1
logs=$(mktemp -d "$PWD/.build/check-logs/run.XXXXXX") || exit 1
trap 'rmdir "$logs" 2>/dev/null || true' EXIT
failed=0; step_index=0

step() {
  local name=$1; shift
  step_index=$((step_index + 1))
  local log="$logs/$(printf '%02d' "$step_index").log"
  if "$@" >"$log" 2>&1; then
    echo "ok    $name"
    rm -f "$log"
  else
    failed=1
    echo "FAIL  $name"
    # Swift Testing reports failures before a long tail of passing tests. Search the whole log first.
    grep -n -i -E '✘|error:|fatal error|expectation failed|recorded an issue|(^|[[:space:]])(FAIL|FAILED)(:|[[:space:]]|$)|(^|[[:space:]])[A-Za-z_][A-Za-z_0-9.]*Error:' "$log" | head -20 | cut -c1-300 || true
    tail -20 "$log" | cut -c1-300
    echo "full log: $log"
  fi
}

step "debug seams" scripts/check-debug-seams.sh
step "decision numbers" scripts/check-decisions.sh
step "copy terms" scripts/check-copy.sh
step "stored keys" scripts/check-stored-keys.sh
step "tooling tests" python3 -B -m unittest discover -s scripts/tests -p 'test_*.py'
step "Core tests" swift test --package-path Packages/CacheDropCore
if [ "$fast" -eq 0 ]; then
  step "Core tests, strict pool" env LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 swift test --package-path Packages/CacheDropCore --skip "$guard"
  step "pool guard, strict pool, alone" env LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 swift test --package-path Packages/CacheDropCore --filter "$guard"
  step "StorageAlerts tests" swift test --package-path Packages/StorageAlerts
  if [ "$failed" -ne 0 ]; then
    echo "Skipping app builds: preceding checks failed."
    exit "$failed"
  fi
  step "app build" xcodebuild build -project CacheDrop/CacheDrop.xcodeproj -scheme CacheDrop -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode
  if [ "$failed" -eq 0 ]; then
    step "Release exclusion check" scripts/check-release.sh
  else
    echo "Skipping Release: Debug app build failed."
  fi
fi
exit $failed
