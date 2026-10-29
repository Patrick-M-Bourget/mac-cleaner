# CacheDrop (mac-cleaner)

CacheDrop is a native SwiftUI storage cleaner for macOS. Its former name was Still: only the one-time migrations (`LegacyStillMigration`, `RenamedPreferenceKeys` with the former keys in `PreferenceKeys`, the `Still.observedAt` fallback in `AlertOpenContext`) and the protection of Still's old folders and bundle IDs still name it. It finds space you can reclaim and cleans what you choose. The project is being reset after the Codex era. `docs/RESET.md` is the current plan, and its **Decisions** section overrides any older doc. The UI authority is the prototype `docs/visual/preview.html` in full mode, not M1 mode.
Behavior the prototype can't show (safety rules, actions, dry run, measured space, access) is in `docs/SPEC.md`.

The Codex-era control docs, validation reports and screenshots are archived at tag `archive/codex-era`. Read them for history only. Never treat them as scope or gates.

GitHub account: `Patrick-M-Bourget`. Run `gh auth status` before any `git push`.

## Build and test

Full Xcode is installed, but `xcode-select` points at the Command Line Tools. Set `DEVELOPER_DIR` for each command instead of changing that:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path Packages/CacheDropCore
xcodebuild build -project CacheDrop/CacheDrop.xcodeproj -scheme CacheDrop -destination 'platform=macOS' -derivedDataPath .build/xcode
open .build/xcode/Build/Products/Debug/CacheDrop.app
```

The test that cleanup tools never block the concurrency pool (#200) only bites when the pool is held to one thread per core.
Run the core tests that way too after touching how tools run:

```sh
LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 swift test --package-path Packages/CacheDropCore
```

Verify on this Mac, not by pushing to CI. Tests touch only temp fixture folders, never real user paths.

UI tests drive the screen, so run them only when the user isn't using it. Run only the journey you changed, and always turn off failure diagnostics, which would otherwise save system logs that may include other apps' activity:

```sh
xcodebuild test -project CacheDrop/CacheDrop.xcodeproj -scheme CacheDrop -destination 'platform=macOS' -derivedDataPath .build/xcode -collect-test-diagnostics never -only-testing:CacheDropUITests/<Class>/<test>
```

The scheme keeps no test attachments and never records the screen (#153). Never take full-screen screenshots; capture only CacheDrop's window.

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

### Copy and names

Every string users see follows Decision 92 in `docs/RESET.md`, and every name comes from `GLOSSARY.md`. Add a new term there before using it.
