# Writing UI journeys

Read before writing or changing a test in `CacheDrop/UITests/`. Run journeys with `scripts/ui-journeys.sh`.

## How SwiftUI shows up to XCUITest

Query an element the way the view exposes it. Check the view's modifiers before you write the query.

- **`.buttonStyle(.link)` is a link.** Every in-row action follows Decision 65's rule 3, so Show N more, Stop scan's old link, Review links and Quit X are `app.links[...]`, never `app.buttons[...]`. The `CloseButton` x is a button.
- **`.accessibilityElement(children: .combine)` merges its children into one element.** Its child texts can't be queried, and its `label` may be empty. Assert on a known identifier inside a non-combined view, or search the window (`app.staticTexts.matching(...)`). Example: Smart clean's `smartCleanHeader`.
- **An identifier on a plain container spreads to its children.** A query for it matches several elements, and reading `frame` or `value` fails with "Multiple matching elements". Give the container `.accessibilityElement(children: .contain)` before its identifier (`explorerInspector`), or query `.firstMatch` when any one will do.
- **A `StatusRow` or `SelectionSummary` text carries its words in `value` or `label`.** Read both: `element.value as? String ?? element.label`.
- **A plan item is `planItem-<rule ID>-<name>`** (its Reveal link `planItemReveal-<rule ID>-<name>`), so same-named items of two rules stay apart (#744). A subscript query allows 128 characters; match a longer identifier with a predicate, as `overviewLocation:` does.
- **Off-screen rows may not exist.** Use `revealAndClick` and the existing wait helpers (`waitForCatalogScan`, `waitForScannedFolder`) rather than bare `exists`.

## Fixtures

- Every journey uses `configureIsolatedState` and `configureCatalogHome`. Nothing reads the real home, apps or caches.
- **The fixture home is also the system root.** `configureCatalogHome` makes the test home stand in for both the home and `/`, so code that scans both roots must de-duplicate: in journeys they are the same folder (#719 once listed a driver twice).
- **A process a journey starts is stopped in `defer`** (`terminate()` then `waitUntilExit()`). A killed run still leaks it; the script's cleanup covers `cachedrop-test-*` paths, so name fixture folders that way.
- **The test runner is sandboxed.** Every file it writes is quarantined, and it can't clear that, so it can't launch an executable it wrote (EPERM, #383). Start fixture processes from system binaries (`/bin/sh` with a script under `.cachedrop-test-*`), as the fake npm does.
- **Verify fixture app signatures before launch.** A system executable copied inside an app bundle needs a new local bundle signature; its original signature is invalid there. Core fixtures sign and verify their generated bundles. A UI journey without a launchable fixture skips before trying to open it (#383), so tests never provoke a damaged-app dialog. The DEBUG app makes a fixture app launchable only behind its own switch (`FixtureAppPresence.quitJourneyApps`): `CACHEDROP_TEST_PREPARE_SYNTH_APP` (Synth) and `CACHEDROP_TEST_PREPARE_CHROME_APP` (a Google Chrome stand-in that holds Chrome's real per-profile caches, #566) and `CACHEDROP_TEST_PREPARE_ANDROID_STUDIO_APP` (an Android Studio stand-in run as `emulator`, holding Android items in two review groups, #564).
- **The trial (#595).** `CACHEDROP_TEST_LICENSE_GATING=1` turns gating on for a disposable run and `CACHEDROP_TEST_TRIAL_USED` (bytes) starts its in-memory count, so a journey reaches the cap without cleaning 2 GB; the build setting stays off.
- **Remembered folders are in memory only.** At launch, no folder is scanned yet, so Explore storage leads to Locations until the launch recheck ends. To test a recheck with the explorer open, scan a folder first, then press ⌘R.
- Debug seams that slow work down: `CACHEDROP_TEST_FOLDER_SCAN_PAUSE` (seconds, up to 10, or `hold` until Stop scan), `CACHEDROP_TEST_CLEANUP_PAUSE` (5 s per item), `CACHEDROP_TEST_RESCAN_PAUSE` (seconds, up to 20, holding the rescan after a run that reads only what the run touched, Decisions 133 and 134), `CACHEDROP_TEST_REVIEW_PAUSE` (seconds, up to 10, holding the review sheet's checks; Cancel ends it) and `CACHEDROP_TEST_CAPACITY_PAUSE` (seconds, up to 5, holding each startup-volume capacity read so "Refreshing…" stays on screen, #655). With the review sheet opening at the click (Decision 126), wait for its Clean up to be enabled, as `cleanUpFromReview` does, before clicking it. Each XCUITest existence check costs about a second.

## Visual comparisons

When checking layout-preserving changes, run `scripts/visual-check.py capture --scenario NAME [DIR]` before and after the change. **Capture drives the screen: run only when the Mac is free.** The command builds the tests, opts into `VisualCaptureUITests` with the scenario in its environment, and captures only CacheDrop's window. The normal journey suite skips this test. A scenario is a `case` in `VisualCaptureUITests`: the fixtures it adds to the catalog home and the pages it shows, one after another, in light then dark. Add a scenario there and to `SCENARIOS` in the script, never by editing the test for one run:

- `overview` (the default): Overview, then the Cleanup plan.
- `audio-software`: #719's Audio software rows (`addAudioSoftware`). `sounds` is Applications with Show sounds open near the top of the page; `drivers` scrolls on to the opened Drivers group. Scroll a page with `reveal(_:in:nearTop:)`, which finds its scroll view through `app.scrollViews`; `window.scrollViews` matched nothing when #719 was captured.

Without DIR, the captures go to a fresh folder in the temp directory, and the command prints it. A DIR must be new and outside the checkout; an existing folder is refused.

Both runs need the same Mac, display scale, system accent, text size and accessibility settings. The fixture fixes the catalog, capacity, file dates, language, appearance and 1000×760-point window on the primary display. It waits for the scan, parks the pointer outside the window before each capture and leaves personal app state untouched.

Each output folder holds one PNG per page and appearance (`<page>-light.png`, `<page>-dark.png`) and `manifest.json`; commit neither. The manifest explicitly records window-local masks for the native title bar/corners and live capacity/scan timestamp labels. Inspect these rectangles when assessing a comparison; all other pixels participate. Compare captures of one scenario: two manifests with different pages are refused.

Compare without driving the screen:

```sh
# One-time setup, outside the checkout:
python3 -m venv /tmp/cachedrop-visual-tools
/tmp/cachedrop-visual-tools/bin/pip install Pillow
# Then compare using that environment:
/tmp/cachedrop-visual-tools/bin/python scripts/visual-check.py compare /absolute/path/before /absolute/path/after
```

Exit 0 means every unmasked pixel matches, 1 means a visual difference, and 2 means invalid inputs. Different dimensions fail rather than resizing. The report includes raw changes, unmasked changes and the maximum channel difference. `--tolerance 1` explicitly allows a one-level channel difference; the default is exact. Capture logs remain in `.build/visual-capture.log`; screenshots are never XCTest attachments.
