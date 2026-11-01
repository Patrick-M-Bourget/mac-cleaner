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
- **Remembered folders are in memory only.** At launch, no folder is scanned yet, so Explore storage leads to Locations until the launch recheck ends. To test a recheck with the explorer open, scan a folder first, then press ⌘R.
- Debug seams that slow work down: `CACHEDROP_TEST_FOLDER_SCAN_PAUSE` (seconds, up to 10, or `hold` until Stop scan), `CACHEDROP_TEST_CLEANUP_PAUSE` (5 s per item) and `CACHEDROP_TEST_REVIEW_PAUSE` (seconds, up to 10, holding the review sheet's checks; Cancel ends it). With the review sheet opening at the click (Decision 126), wait for its Clean up to be enabled, as `cleanUpFromReview` does, before clicking it. Each XCUITest existence check costs about a second.

## Visual comparisons

When checking layout-preserving changes, use `scripts/visual-check.py capture /absolute/path/before`, then repeat with a new `after` directory on the changed branch. **Capture drives the screen: run only when the Mac is free.** The command builds the tests, opts into `VisualCaptureUITests`, and captures only CacheDrop's window. The normal journey suite skips this test.

Both runs need the same Mac, display scale, system accent, text size and accessibility settings. The fixture fixes the catalog, capacity, file dates, language, appearance and 1000×760-point window on the primary display. It waits for the scan, parks the pointer outside the window and captures Overview and Cleanup plan in light and dark. It leaves personal app state untouched.

Outputs must be new directories outside the checkout. They contain four PNGs and `manifest.json`; commit neither. The manifest explicitly records window-local masks for the native title bar/corners and live capacity/scan timestamp labels. Inspect these rectangles when assessing a comparison; all other pixels participate.

Compare without driving the screen:

```sh
# One-time setup, outside the checkout:
python3 -m venv /tmp/cachedrop-visual-tools
/tmp/cachedrop-visual-tools/bin/pip install Pillow
# Then compare using that environment:
/tmp/cachedrop-visual-tools/bin/python scripts/visual-check.py compare /absolute/path/before /absolute/path/after
```

Exit 0 means every unmasked pixel matches, 1 means a visual difference, and 2 means invalid inputs. Different dimensions fail rather than resizing. The report includes raw changes, unmasked changes and the maximum channel difference. `--tolerance 1` explicitly allows a one-level channel difference; the default is exact. Capture logs remain in `.build/visual-capture.log`; screenshots are never XCTest attachments.
