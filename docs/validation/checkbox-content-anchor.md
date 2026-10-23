# Checkbox content movement — reported, not reproduced

The user reports intermittent content shifting/scrolling inside the window after checkbox clicks, on folder inspection or Cleanup plan (exact screen uncertain). This report remains open. No application layout or selection code was changed, and these passing checks do not establish a fix.

## Checks performed

The focused native journeys select and deselect category/file checkboxes using owned disposable files. They assert the original outer window frame and the clicked control’s viewport frame, then verify the public selection state. File controls must be fully inside the visible scroll viewport; accessibility `isHittable` alone proved insufficient for off-screen rows. Selection completion uses a bounded public-state expectation.

- Small 12-file, long-path fixtures passed in both screens at `a8b06d2`, [run 39971673559](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39971673559).
- Larger 120-file fixtures, including the lowest fully visible checkbox after scrolling, passed both journeys at `ef89db63c9b169027e8f8ea1e109baf3002ead63`, [run 39972806712](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39972806712): **2/2**, zero failures, 97.870 seconds. Category selection cycles are also covered. The hosted run passed existing core/alert/adapter checks and built the native UI runner.
- The earlier inspection failure at `223b256` clicked an off-screen control, so it is a harness error rather than evidence of the reported content jump. The visible-viewport guard corrected that precondition.

Manual invocation: `gh workflow run native.yml --ref fix/checkbox-content-anchor -f suite=selection`. Push/PR workflows still run the full native suite. Application source remains identical to the accepted `524f878`; the two additional journeys are regression coverage, not a new tested application build. Hosted checks use macOS 26.6.2/arm64 and a minimum-sized window. No personal folder scan or cleanup was performed.

## Still needed

A short recording of the actual occurrence, or exact steps including the screen, checkbox, window size, search/filter state and whether the item inspector is open. Current checks compare settled control positions; they cannot exclude a brief movement that returns before the assertion, or a data-specific case absent from these fixtures. Capture the reproduction before changing production layout. The current Release artifact remains `Still-524f878.app`.
