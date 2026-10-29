#!/bin/bash
# Runs CacheDrop's UI journeys and prints one line per test.
#
#   scripts/ui-journeys.sh testName [Class/testName ...]   the journeys you touched
#   scripts/ui-journeys.sh --all                          the whole UI suite
#   --no-build                                            reuse the last build-for-testing
#
# A bare test name is resolved to its class, including tests written in `extension SomeUITests` blocks. Before and after
# the run it stops fixture processes a killed run can leave behind (#380) and any CacheDrop this checkout launched. A
# failed build stops here, so tests never run against a stale build. Failure diagnostics stay off (see CLAUDE.md).
# The run drives the screen: use it only when nobody is using this Mac.
set -uo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

build=1; all=0; tests=()
for arg in "$@"; do
  case "$arg" in
    --no-build) build=0 ;;
    --all) all=1 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) tests+=("$arg") ;;
  esac
done
if [ "$all" -eq 0 ] && [ "${#tests[@]}" -eq 0 ]; then echo "Name at least one test, or --all." >&2; exit 2; fi

# Test name → Class/test, from the class or extension the method sits in.
resolve() {
  case "$1" in */*) echo "$1"; return 0 ;; esac
  local file line class
  file=$(grep -l "func $1(" CacheDrop/UITests/*.swift | head -1)
  [ -n "$file" ] || { echo "No UI test named $1" >&2; return 1; }
  line=$(grep -n "func $1(" "$file" | head -1 | cut -d: -f1)
  class=$(head -n "$line" "$file" | grep -E '^(final class|class|extension) [A-Za-z]+' | tail -1 | sed -E 's/^(final class|class|extension) ([A-Za-z]+).*/\2/')
  echo "$class/$1"
}

only=()
for test in ${tests[@]+"${tests[@]}"}; do
  resolved=$(resolve "$test") || exit 2
  only+=("-only-testing:CacheDropUITests/$resolved")
done

checkout="$(pwd)"
cleanup() {
  pkill -f 'cachedrop-test-' 2>/dev/null
  pkill -f "$checkout/.build/xcode/.*/CacheDrop.app" 2>/dev/null
  return 0
}
cleanup

log=$(mktemp -t cachedrop-ui)
project=(-project CacheDrop/CacheDrop.xcodeproj -scheme CacheDrop -destination 'platform=macOS' -derivedDataPath .build/xcode)
if [ "$build" -eq 1 ]; then
  if ! xcodebuild build-for-testing "${project[@]}" >"$log" 2>&1; then
    grep -E 'error:' "$log" | head -20
    echo "build-for-testing failed; full log: $log"
    exit 1
  fi
fi

xcodebuild test-without-building "${project[@]}" -collect-test-diagnostics never ${only[@]+"${only[@]}"} >"$log" 2>&1
status=$?
cleanup

grep -E "Test Case '.*' (passed|failed|skipped)|\.swift:[0-9]+: error" "$log" \
  | sed -E "s#^.*/UITests/##; s/^Test Case '-\[CacheDropUITests\.([A-Za-z]+) ([A-Za-z0-9_]+)\]' /\1\/\2 /"
echo "xcodebuild exit $status; full log: $log"
exit $status
