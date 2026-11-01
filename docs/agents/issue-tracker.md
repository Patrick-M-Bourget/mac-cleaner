# Issue tracker: GitHub

Repository: Patrick-M-Bourget/mac-cleaner.
Use the gh CLI for issue operations.

- Publishing a ticket means creating a GitHub issue.
- Read the issue body, comments and labels before working on it.
- For multiline content, use --body-file.
- Create blockers before dependent tickets.
- Represent blocking edges with GitHub native issue dependencies.
  Use the blocker’s database ID, not its issue number.
- Add an edge with `gh api --method POST repos/Patrick-M-Bourget/mac-cleaner/issues/<dependent-number>/dependencies/blocked_by -F issue_id=<blocker-database-id>`.
- If native dependencies are unavailable, list blocking issues
  under “Blocked by” in the dependent issue.
- When splitting an existing issue, link tickets as its sub-issues;
  otherwise reference the parent in each child.
- Do not close or modify a parent merely because tickets were created.

## Reading, checking and editing a batch

`scripts/issues.py` (`--help` for usage) works on many tickets at once, in one GraphQL call per 40 tickets:

- `dump 590-645` or `dump --milestone TITLE`: each ticket's raw body with its labels, milestone, parent, blockers and sub-issues. Read a batch this way rather than one `gh issue view` per ticket.
- `check` (same arguments): run it after creating or editing a batch and fix every line it prints. It catches malformed references (`##590`), a `## Parent` section that disagrees with the native parent, conflicting triage labels, cited Decisions that don't exist, and leftover "transfer it there" notes. Missing blocking links, stale questions and contradictions between tickets stay a reviewer's judgement.
- `edit N --replace OLD NEW ... [--title T]`: changes the body only if every OLD matches exactly once, so a failed match never posts half an edit. Copy OLD from `dump`: GitHub stores some references as `owner/repo#N` even where the page shows `#N`.
- `decision N [--site]`: prints one whole Decision from `docs/RESET.md` (`--site`: cachedrop-website's `docs/DECISIONS.md`). Read the whole entry before saying what it covers: amendments often sit mid-paragraph.

## Moving a ticket to cachedrop-website

`gh issue transfer N Patrick-M-Bourget/cachedrop-website` keeps the parent and blocking links (they work across the two repos) but drops the milestone and any label the website lacks (`parity`, `area:*`, `size:*`). Right after the move the API can report the links as missing for a moment; adding them again then fails with 422 "already taken", so read them back before re-adding. GitHub also rewrites some references to the moved ticket in other bodies, so `dump` again before editing those.

## PR closing references

After creating or editing a PR, and immediately before merging, compare GitHub's actual closing references with the issues the work completes. Use an explicit empty expectation for partial-ticket PRs. GitHub can interpret a closing keyword even when the surrounding sentence negates it; check its metadata rather than the prose.

Replace `123` with the PR number:

```sh
scripts/check-pr-closing.py 123 --expect-none
scripts/check-pr-closing.py 123 --expect 45 67
```

Bare issue numbers belong to this checkout's GitHub repository. Use `owner/repository#number` for another repository. The command reads all pages of closing references through authenticated `gh`, compares the exact set, and prints the checked head SHA. It is read-only and grants no merge approval. Merge only after the owner's confirmation, using that head SHA; repeat validation after any PR body or head change.

Exit 0 means an exact match, 1 reports missing or unexpected issue links, and 2 means invalid input or unavailable, incomplete or changing GitHub metadata. Correct unintended closing links or expectations before proceeding. For partial work, leave the parent issue open and update its completed checklist entries after merge.

PRs as a request surface: no.
