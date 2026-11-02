#!/bin/bash
# The pass stamp: proof that scripts/check.sh passed on exactly the content about to be committed (#667).
#
#   scripts/check-stamp.sh write               record the tree of the files as they are now (check.sh calls it)
#   scripts/check-stamp.sh matches             exit 0 when the index is the recorded tree
#   scripts/check-stamp.sh matches --all       ... the index plus tracked changes (`git commit -a`)
#   scripts/check-stamp.sh matches --working   ... the working tree, untracked files too (a `git add` in the same
#                                              command, which runs after the check)
#
# A commit that changes no content (a message-only --amend) also passes. The stamp lives in this worktree's git dir,
# so each worktree has its own. A Claude Code hook in the owner's user settings calls `matches` before `git commit`
# and refuses the commit when it fails.
set -uo pipefail
cd "$(dirname "$0")/.."
stamp=$(git rev-parse --git-path check-pass) || exit 1

# The tree of the index after `git add $1`, built in a scratch copy so the real index is untouched.
tree_after_add() {
  local scratch status
  scratch=$(mktemp) || return 1
  cp "$(git rev-parse --git-path index)" "$scratch" 2>/dev/null || : >"$scratch"
  GIT_INDEX_FILE=$scratch git add "$1" >/dev/null 2>&1 && GIT_INDEX_FILE=$scratch git write-tree 2>/dev/null
  status=$?
  rm -f "$scratch"
  return $status
}

case "${1:-}" in
  write)
    tracked=$(tree_after_add -u) && everything=$(tree_after_add -A) ||
      { echo "check-stamp: unmerged files; no stamp written" >&2; exit 1; }
    printf '%s\n%s\n' "$tracked" "$everything" >"$stamp"
    ;;
  matches)
    case "${2:-}" in
      --all) tree=$(tree_after_add -u); line=1 ;;
      --working) tree=$(tree_after_add -A); line=2 ;;
      *) tree=$(git write-tree 2>/dev/null); line=0 ;;
    esac
    [ -n "${tree:-}" ] || { echo "Resolve the unmerged files first." >&2; exit 1; }
    if [ -f "$stamp" ]; then
      if [ "$line" -eq 0 ]; then grep -qx "$tree" "$stamp" && exit 0
      else [ "$(sed -n "${line}p" "$stamp")" = "$tree" ] && exit 0; fi
    fi
    if ! git rev-parse -q --verify MERGE_HEAD >/dev/null && [ "$(git rev-parse -q --verify 'HEAD^{tree}')" = "$tree" ]; then
      exit 0
    fi
    echo "scripts/check.sh hasn't passed on the content being committed. Run it, then commit exactly what it tested." >&2
    exit 1
    ;;
  *)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
