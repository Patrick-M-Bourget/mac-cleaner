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
