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
# A journey asked for (each named test, or every test in the UI sources for --all) that reports no passed, failed or
# skipped line, as when the runner restarts mid-run, is named ("No result: Class/test") and rerun once on the same
# build. The last line and exit status then cover both runs: a failure, or a journey still without a result, is non-zero.
# When no journey reports at all, the runner likely didn't start: that is said, nothing is rerun, and the exit is non-zero.
# The run drives the screen: use it only when nobody is using this Mac.
set -uo pipefail
TMPDIR="${TMPDIR:-/tmp}"
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

build=1; all=0; tests=()
for arg in "$@"; do
  case "$arg" in
    --no-build) build=0 ;;
    --all) all=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) tests+=("$arg") ;;
  esac
done
if [ "$all" -eq 0 ] && [ "${#tests[@]}" -eq 0 ]; then echo "Name at least one test, or --all." >&2; exit 2; fi

# Every UI test as Class/test: each `func test…()` under the class or extension it sits in.
all_tests() {
  awk '/^(final class|class|extension) [A-Za-z0-9_]+/ { owner = $0; sub(/^(final class|class|extension) /, "", owner); sub(/[^A-Za-z0-9_].*/, "", owner) }
       owner != "" && match($0, /func test[A-Za-z0-9_]*\(\)/) { print owner "/" substr($0, RSTART + 5, RLENGTH - 7) }' CacheDrop/UITests/*.swift
}

# Test name → Class/test.
resolve() {
  case "$1" in */*) echo "$1"; return 0 ;; esac
  local found
  found=$(all_tests | grep -m1 "/$1\$")
  [ -n "$found" ] || { echo "No UI test named $1" >&2; return 1; }
  echo "$found"
}

requested=()
for test in ${tests[@]+"${tests[@]}"}; do
  resolved=$(resolve "$test") || exit 2
  requested+=("$resolved")
done
[ "${#requested[@]}" -gt 0 ] || while read -r test; do requested+=("$test"); done < <(all_tests)

# The requested tests a log has no passed, failed or skipped line for.
unreported() {
  local log="$1" test; shift
  for test in "$@"; do
    grep -qE "Test Case '-\[CacheDropUITests\.${test%/*} ${test#*/}\]' (passed|failed|skipped)" "$log" || echo "$test"
  done
}

# One line per result, failure line and runner restart.
report() {
  grep -E "Test Case '.*' (passed|failed|skipped)|\.swift:[0-9]+: error|Restarting after unexpected exit" "$1" \
    | sed -E "s#^.*/UITests/##; s/^Test Case '-\[CacheDropUITests\.([A-Za-z0-9_]+) ([A-Za-z0-9_]+)\]' /\1\/\2 /"
}

checkout="$(pwd)"
cleanup() {
  pkill -f 'cachedrop-test-' 2>/dev/null
  pkill -f "$checkout/.build/xcode/.*/CacheDrop.app" 2>/dev/null
  return 0
}
cleanup

log=$(mktemp "${TMPDIR%/}/cachedrop-ui.XXXXXXXX")
project=(-project CacheDrop/CacheDrop.xcodeproj -scheme CacheDrop -destination 'platform=macOS' -derivedDataPath .build/xcode)
if [ "$build" -eq 1 ]; then
  if ! xcodebuild build-for-testing "${project[@]}" >"$log" 2>&1; then
    grep -E 'error:' "$log" | head -20
    echo "build-for-testing failed; full log: $log"
    exit 1
  fi
fi

# Runs the given -only-testing arguments (none: the whole suite) into a log, prints its results, returns xcodebuild's exit.
run_tests() {
  local into="$1" code; shift
  xcodebuild test-without-building "${project[@]}" -collect-test-diagnostics never "$@" >"$into" 2>&1
  code=$?
  cleanup
  report "$into"
  return $code
}

only=()
[ "${#tests[@]}" -eq 0 ] || for test in "${requested[@]}"; do only+=("-only-testing:CacheDropUITests/$test"); done
run_tests "$log" ${only[@]+"${only[@]}"}
status=$?

missing=()
while read -r test; do missing+=("$test"); done < <(unreported "$log" "${requested[@]}")
if [ "${#missing[@]}" -eq 0 ]; then
  echo "xcodebuild exit $status; full log: $log"
  exit $status
fi

# No journey reported at all: the runner most likely never started (as with "Timed out while enabling automation mode").
# A rerun would only repeat that.
if [ "${#missing[@]}" -eq "${#requested[@]}" ]; then
  [ "$status" -ne 0 ] || status=1
  echo "xcodebuild exit $status; no journey reported, so the runner likely didn't start; full log: $log"
  exit $status
fi

# The runner can restart or stop mid-run and leave journeys without a result (#724): rerun those once on the same build.
for test in "${missing[@]}"; do echo "No result: $test"; done
echo "Rerunning ${#missing[@]} without a result once"
rerun_log=$(mktemp "${TMPDIR%/}/cachedrop-ui.XXXXXXXX")
only=()
for test in "${missing[@]}"; do only+=("-only-testing:CacheDropUITests/$test"); done
run_tests "$rerun_log" "${only[@]}"
rerun_status=$?

still=$(unreported "$rerun_log" "${missing[@]}" | paste -sd ' ' -)
result=0
if [ "$rerun_status" -ne 0 ]; then result=$rerun_status
elif [ -n "$still" ] || grep -qE "Test Case '.*' failed" "$log"; then result=1
fi
echo "xcodebuild exit $status, rerun exit $rerun_status${still:+, still no result: $still}; full logs: $log $rerun_log"
exit $result
