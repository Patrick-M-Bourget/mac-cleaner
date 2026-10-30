# CacheDrop (mac-cleaner)

CacheDrop is a native SwiftUI storage cleaner for macOS. Its former name was Still: only the one-time migrations (`LegacyStillMigration`, `RenamedPreferenceKeys` with the former keys in `PreferenceKeys`, the `Still.observedAt` fallback in `AlertOpenContext`) and the protection of Still's old folders and bundle IDs still name it. It finds space you can reclaim and cleans what you choose. The project is being reset after the Codex era. `docs/RESET.md` is the current plan, and its **Decisions** section overrides any older doc. The UI authority is the prototype `docs/visual/preview.html` in full mode, not M1 mode.
Behavior the prototype can't show (safety rules, actions, dry run, measured space, access) is in `docs/SPEC.md`.

The Codex-era control docs, validation reports and screenshots are archived at tag `archive/codex-era`. Read them for history only. Never treat them as scope or gates.

GitHub account: `Patrick-M-Bourget`. Run `gh auth status` before any `git push`.

## Build and test

`scripts/check.sh` runs what CI runs, one line per step: the source checks (test seams, Decision numbering, copy terms, stored keys), tooling tests, the Core suite normal and on the strict pool (#200, with its guard run alone, #242), StorageAlerts' suite, the Debug app build and the Release exclusion check. `--fast` stops after the Core suite. Failed steps keep separate full logs under `.build/check-logs/` and print their paths; earlier failures skip app builds. Full Xcode is installed, but `xcode-select` points at the Command Line Tools, so commands of your own set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; the scripts do. The app it builds is `.build/xcode/Build/Products/Debug/CacheDrop.app`.

Run StorageAlerts alone with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StorageAlerts`.

Verify on this Mac, not by pushing to CI. Tests touch only temp fixture folders, never real user paths.

UI tests drive the screen, so run them only when the user isn't using it. Run only the journeys you changed with `scripts/ui-journeys.sh <testName>...` (`--all` for the suite): it resolves each test's class, clears leftover fixtures, stops on a failed build, keeps failure diagnostics off (they would save system logs that may include other apps' activity) and prints one line per test. Before writing or changing a journey, read `docs/agents/ui-testing.md`: how SwiftUI views appear to XCUITest, and the sandboxed runner's limits and the opt-in window comparison tool.

The scheme keeps no test attachments and never records the screen (#153). Never take full-screen screenshots; capture only CacheDrop's window.

## Workflow

- One logical change per commit and about 500 lines or less per PR. Run `scripts/check.sh` before every commit.
- Push a branch, open a PR (`/pr`) based on `main`, and say what to smoke-test locally. After creating or editing a PR and immediately before merging, validate its closing references as `docs/agents/issue-tracker.md` describes. Merge only after the user confirms. A PR based on another PR's branch closes when that branch is deleted on merge.
- Commit no screenshots, evidence reports or session essays. A finding that matters goes into `docs/RESET.md` (Decisions) or an issue.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for Patrick-M-Bourget/mac-cleaner, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Parallel ticket batches

Running several tickets at once with one agent each: `docs/agents/implementer-brief.md`.

### Domain docs

Single-context. See `docs/agents/domain.md`.

### Copy and names

Every string users see follows Decision 92 in `docs/RESET.md`, and every name comes from `GLOSSARY.md`. Add a new term there before using it.
