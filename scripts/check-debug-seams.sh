#!/bin/bash
# Fails when a test seam or a process signal sits in app or library code outside `#if DEBUG`.
#
# A release build must read no `CACHEDROP_TEST_*` environment switch and hold no code that signals another app
# (`kill(`, `SIGTERM`, `SIGKILL`): production quits apps only through `NSRunningApplication.terminate()` (Decision 79).
# A line that signals only what CacheDrop started itself, or probes with signal 0, says why on the same line:
# `// seam-check: allow (reason)`. Runtime guards on `isDisposableTest` are fine: it is false in a release build.
# Tests and UI tests are not checked.
#
#   scripts/check-debug-seams.sh        exit 0 when clean; otherwise prints file:line: text for each finding
set -uo pipefail
cd "$(dirname "$0")/.."

files=$(git ls-files 'CacheDrop/App/*.swift' 'Packages/*/Sources/*.swift' 'CacheDrop/Packages/*/Sources/*.swift')
[ -n "$files" ] || { echo "No Swift sources found" >&2; exit 2; }

# shellcheck disable=SC2086
awk '
  FNR == 1 { depth = 0 }
  # Each #if level remembers whether its live branch is DEBUG-only.
  /^[[:space:]]*#if[[:space:]]/ { depth++; debug[depth] = ($0 ~ /#if[[:space:]]+DEBUG([[:space:]]|$)/); next }
  /^[[:space:]]*#elseif[[:space:]]/ { debug[depth] = 0; next }
  /^[[:space:]]*#else([[:space:]]|$)/ { debug[depth] = 0; next }
  /^[[:space:]]*#endif/ { if (depth > 0) depth--; next }
  /^[[:space:]]*\/\// { next }
  /seam-check: allow \(/ { next }
  /CACHEDROP_TEST_|[^A-Za-z_.]kill\(|SIGTERM|SIGKILL/ {
    inDebug = 0
    for (i = 1; i <= depth; i++) if (debug[i]) inDebug = 1
    if (!inDebug) { printf "%s:%d: %s\n", FILENAME, FNR, $0; found = 1 }
  }
  END { exit found }
' $files
status=$?
[ $status -eq 0 ] || echo "Test seams and process signals belong inside #if DEBUG (scripts/check-debug-seams.sh)." >&2
exit $status
