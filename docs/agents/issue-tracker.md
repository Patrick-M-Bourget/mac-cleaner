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

PRs as a request surface: no.
