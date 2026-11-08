#!/bin/bash
# The UI suite stamp: proof that a full `scripts/ui-journeys.sh --all` passed on the release's app code (#807).
#
#   scripts/ui-suite-stamp.sh current            print HEAD when CacheDrop/ and Packages/ match it (the run can be stamped)
#   scripts/ui-suite-stamp.sh write COMMIT       record COMMIT as the last full-suite pass (ui-journeys.sh calls it)
#   scripts/ui-suite-stamp.sh matches COMMIT     exit 0 when the stamped commit's CacheDrop/ and Packages/ are COMMIT's
#
# Only the app and UI-test sources count, so commits that change docs, scripts or docs/releases/ keep the stamp valid
# and the release commit itself needs no rerun. The stamp lives in the repository's common git dir, so a run in any
# worktree counts for the release, which ship-release.sh checks with `matches` before building. Merging stays ungated.
set -uo pipefail
cd "$(dirname "$0")/.."
sources=(CacheDrop Packages)
rerun="Run scripts/ui-journeys.sh --all on that commit (nobody using this Mac), then rerun."

# The trees of the sources in a commit, one line.
source_trees() {
  local dir
  for dir in "${sources[@]}"; do git rev-parse -q --verify "$1:$dir" || echo "-"; done | paste -sd ' ' -
}

case "${1:-}" in
  current)
    head=$(git rev-parse -q --verify HEAD 2>/dev/null) || { echo "No UI suite stamp for this run: not a git checkout." >&2; exit 1; }
    if [ -n "$(git status --porcelain -- "${sources[@]}")" ]; then
      echo "No UI suite stamp for this run: CacheDrop/ or Packages/ has uncommitted changes." >&2
      exit 1
    fi
    echo "$head"
    ;;
  write)
    commit=$(git rev-parse -q --verify "${2:-}^{commit}") || { echo "ui-suite-stamp: no commit ${2:-}" >&2; exit 2; }
    echo "$commit" >"$(git rev-parse --git-common-dir)/ui-suite-pass"
    ;;
  matches)
    commit=$(git rev-parse -q --verify "${2:-}^{commit}") || { echo "ui-suite-stamp: no commit ${2:-}" >&2; exit 2; }
    stamp="$(git rev-parse --git-common-dir)/ui-suite-pass"
    if [ ! -s "$stamp" ]; then
      echo "No full UI suite pass is recorded. $rerun" >&2
      exit 1
    fi
    stamped=$(head -1 "$stamp")
    if git cat-file -e "$stamped^{commit}" 2>/dev/null && [ "$(source_trees "$stamped")" = "$(source_trees "$commit")" ]; then
      echo "The full UI suite passed on ${stamped:0:12}, whose CacheDrop/ and Packages/ match ${commit:0:12}."
      exit 0
    fi
    echo "The last full UI suite pass is for ${stamped:0:12}, whose CacheDrop/ or Packages/ differ from ${commit:0:12}. $rerun" >&2
    exit 1
    ;;
  *)
    sed -n '2,/^[^#]/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
