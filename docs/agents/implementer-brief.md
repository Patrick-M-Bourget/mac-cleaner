# Parallel ticket batches

How to run a batch of tickets with one implementer agent per ticket. The orchestrator follows **Orchestrator**; each implementer gets the **Implementer brief** with its ticket, worktree, branch and Decision number filled in.

## Orchestrator

1. **Branches.** Create the batch branch (`ship/batch-N`) from `origin/main`, then one worktree per ticket beside the repo: `git worktree add ../mac-cleaner-<ticket> -b fix/<ticket>-<slug> ship/batch-N`.
2. **Decision numbers.** Give each ticket the next free Decision number, in batch order, and note in the hand-off which number the next batch or parked work starts at.
3. **Overlap.** When two tickets touch the same code, tell each agent which part the other owns.
4. **Prompts.** Spawn the agents in parallel. Each prompt carries the brief below, filled in, plus the session's commit trailer lines.
5. **Merge.** Merge each finished branch into the batch branch (`--no-ff`, with the trailer lines). `docs/RESET.md` merges by union, so put its Decisions back in order if `scripts/check-decisions.sh` complains.
6. **Verify.** Run the core tests, the strict pool and `build-for-testing` on the batch branch. Then run `scripts/ui-journeys.sh` with every journey the agents named, once nobody is using the screen.
7. **Review.** Run `/code-review` against `origin/main`; the reviewer reads `CODING_STANDARDS.md`. Fix real bugs on the batch branch, one commit each, and ticket the judgement calls.
8. **Ship.** Push, open one PR with `/pr`, and merge only on the owner's "merge". Remove the ticket worktrees once it lands.

## Implementer brief

You implement ONE ticket of CacheDrop (Patrick-M-Bourget/mac-cleaner) in your own git worktree: `<worktree>`, branch `<branch>`. Other agents work on other tickets in sibling worktrees at the same time.

**Read first**
- The ticket: `gh issue view <N> -R Patrick-M-Bourget/mac-cleaner`. Its "Decided" or "Expected" wording is approved by the owner and ships unchanged.
- `CLAUDE.md` (build and test), `docs/SPEC.md` (behaviour), the Decisions the ticket cites in `docs/RESET.md`, and `CODING_STANDARDS.md`, which your work will be reviewed against.
- Before touching a UI journey: `docs/agents/ui-testing.md`.

**Work**
- Work only in your worktree. Use the `tdd` skill wherever logic can live in CacheDropCore: red, green, one slice at a time. View layout has no unit seam.
- Keep edits to shared files (`CacheDropApp.swift`, `DesignSystem.swift`, `docs/RESET.md`) small and local; the other agents merge alongside you.
- Record the change as Decision `<number>`, appended to the Decisions list in the style of the others (bold title with date, ticket and what it amends, then plain sentences). Give any older Decision it changes an "amended by Decision `<number>`" pointer, and update `docs/SPEC.md` where it states the old behaviour.
- Update the UI journey of every page you touch so it covers the ticket. Leave running it to the orchestrator: the screen belongs to the owner, so build it (`build-for-testing`) without launching the app.
- Commit small, one logical change each, ending every message with the trailer lines in your prompt. Leave pushing, PRs and issue comments to the orchestrator.

**Done**
- `swift test --package-path Packages/CacheDropCore` passes: single test files while iterating, the full suite once at the end.
- `xcodebuild build` and `build-for-testing` pass, and `scripts/check-debug-seams.sh` is clean.
- Report in 15 lines or fewer:
  - branch, head SHA and commits
  - each acceptance criterion and how it is met and tested
  - the UI tests to run (`Class/test`)
  - what the owner should smoke-test by hand
  - open questions, and anything you did that the ticket didn't ask for

  Claim only what you verified.
