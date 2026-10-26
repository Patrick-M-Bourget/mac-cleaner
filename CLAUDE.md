# Still (mac-cleaner)

A native SwiftUI storage cleaner for macOS. It finds space you can reclaim and cleans what you choose. The project is being reset after the Codex era. `docs/RESET.md` is the current plan, and its **Decisions** section overrides any older doc. The UI authority is the prototype `docs/visual/preview.html` in full mode, not M1 mode.

The Codex-era control docs (SPEC, DESIGN-HANDOFF, MILESTONES, PROTOTYPE-PARITY, FLOW-LOCK, `docs/validation/`, and the rest) are scheduled for removal in reset Phase 1. Read them for history only. Never treat them as scope or gates.

GitHub account: `Patrick-M-Bourget`. Run `gh auth status` before any `git push`.

## Build and test

Full Xcode is installed, but `xcode-select` points at the Command Line Tools. Set `DEVELOPER_DIR` for each command instead of changing that:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path Packages/StillCore
xcodebuild build -project Still/Still.xcodeproj -scheme Still -destination 'platform=macOS' -derivedDataPath .build/xcode
open .build/xcode/Build/Products/Debug/Still.app
```

Verify on this Mac, not by pushing to CI. Tests touch only temp fixture folders, never real user paths.

## Workflow

- One logical change per commit and about 500 lines or less per PR. Run tests and build before every commit.
- Push a branch, open a PR (`/pr`), and say what to smoke-test locally. Merge only after the user confirms.
- Commit no screenshots, evidence reports or session essays. A finding that matters goes into `docs/RESET.md` (Decisions) or an issue.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for Patrick-M-Bourget/mac-cleaner, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context. See `docs/agents/domain.md`.
