# Writing UI journeys

Read before writing or changing a test in `CacheDrop/UITests/`. Run journeys with `scripts/ui-journeys.sh`.

## How SwiftUI shows up to XCUITest

Query an element the way the view exposes it. Check the view's modifiers before you write the query.

- **`.buttonStyle(.link)` is a link.** Every in-row action follows Decision 65's rule 3, so Show N more, Stop scan's old link, Review links and Quit X are `app.links[...]`, never `app.buttons[...]`. The `CloseButton` x is a button.
- **`.accessibilityElement(children: .combine)` merges its children into one element.** Its child texts can't be queried, and its `label` may be empty. Assert on a known identifier inside a non-combined view, or search the window (`app.staticTexts.matching(...)`). Example: Smart clean's `smartCleanHeader`.
- **An identifier on a plain container spreads to its children.** A query for it matches several elements, and reading `frame` or `value` fails with "Multiple matching elements". Give the container `.accessibilityElement(children: .contain)` before its identifier (`explorerInspector`), or query `.firstMatch` when any one will do.
- **A `StatusRow` or `SelectionSummary` text carries its words in `value` or `label`.** Read both: `element.value as? String ?? element.label`.
- **Off-screen rows may not exist.** Use `revealAndClick` and the existing wait helpers (`waitForCatalogScan`, `waitForScannedFolder`) rather than bare `exists`.

## Fixtures

- Every journey uses `configureIsolatedState` and `configureCatalogHome`. Nothing reads the real home, apps or caches.
- **A process a journey starts is stopped in `defer`** (`terminate()` then `waitUntilExit()`). A killed run still leaks it; the script's cleanup covers `cachedrop-test-*` paths, so name fixture folders that way.
- **The test runner is sandboxed.** Every file it writes is quarantined, and it can't clear that, so it can't launch an executable it wrote (EPERM, #383). Start fixture processes from system binaries (`/bin/sh` with a script under `.cachedrop-test-*`), as the fake npm does.
- **Verify fixture app signatures before launch.** A system executable copied inside an app bundle needs a new local bundle signature; its original signature is invalid there. Core fixtures sign and verify their generated bundles. A UI journey without a launchable fixture skips before trying to open it (#383), so tests never provoke a damaged-app dialog.
- **Remembered folders are in memory only.** At launch, no folder is scanned yet, so Explore storage leads to Locations & access until the launch recheck ends. To test a recheck with the explorer open, scan a folder first, then press ⌘R.
- Debug seams that slow a scan down: `CACHEDROP_TEST_FOLDER_SCAN_PAUSE` (seconds, up to 10, or `hold` until Stop scan) and `CACHEDROP_TEST_CLEANUP_PAUSE` (5 s per item). Each XCUITest existence check costs about a second.
