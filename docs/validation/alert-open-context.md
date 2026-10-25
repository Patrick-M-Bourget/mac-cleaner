# Opening an alert with observation context

This completes #27's accepted notification-open contract: Overview shows the time attached to the opened alert, separately from its independent startup-volume observation, and offers an explicit folder choice for a fresh scan. Opening never scans or cleans. Legacy or malformed timestamps show time unavailable. Cancelling the picker keeps the context; Dismiss alert removes the context only. A chosen scan folder follows the existing explicit inspection flow.

The app-owned notification payload carries the observation timestamp. A typed `AlertOpenContext` decodes finite, bounded timestamps; the native delegate stores it before requesting the workspace, so creating/reopening the window retains the context. No notification authorization or login behavior changed in this feature.

## Public behavior verification

TDD used the previously approved public adapter-result and app-journey seams. The timestamp contract first failed because the API was absent; after that vertical slice passed, malformed timestamp cases failed before validation was added. The merged local StorageAlerts package passed 33 tests. Hosted [run 40017317357](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40017317357), source `c2e9a320ac2631eedb708dcf28171c7d8383d650`, passed the same 33 package tests and the one focused native journey in 79.153 seconds, zero failures.

The journey opens dated, legacy and malformed contexts at initial/minimum sizes, verifies the original date or exact unavailable fallback, no automatic inspection, fixed window bounds, explicit native folder-picker cancellation and context dismissal. The DEBUG injector requires the future capability flag and an existing identity-checked disposable root (UUID marker, owner, mode, device/inode); it does not lift notification restrictions. It uses the same typed open route as the native delegate. Tests do not request notification permission, change login registration, access personal folders or execute cleanup.

The earlier native run 40016268055 failed six text assertions because AppKit exposed this static text through accessibility `value`, while the test read its empty `label`. Captures already showed correct visible dates/fallbacks, and picker/dismissal/geometry assertions passed. The corrected journey reads the public native value, preserves its exact expected content checks and stops on the first failure. No product UI change or relaxed expectation was needed. The final run above supersedes that failed test result.

## Design system and visual acceptance

All [12 original captures](../visual/alert-open/manifest.json) were individually viewed: dated, legacy and malformed states in Light/Dark at hosted initial 1024 × 640 and minimum 900 × 640. The existing `SummarySurface` / `StatusRow`, shared spacing/typography and native buttons supply this composition. No new primitive or gallery API was introduced; existing gallery examples already cover those components. Reviewed against the approved native vocabulary: white Light sidebar, near-black Dark reading plane, subdued grouped surface, readable wrapped context, visible actions, independent current-capacity time and stable outer dimensions. Lower Overview rows continue to scroll within the unchanged window.

The manifest preserves source, run, artifact metadata, original export names, dimensions, timestamps and SHA-256 hashes. Later integration merged only separate harness/evidence changes; its `Still/App` tree remains identical to the captured source. Independent review of `25c4626...d9da586` found zero Standards and zero Spec findings; the subsequent test-only accessibility read correction retains the same public assertions.

This is fixture-backed context/navigation qualification, not proof of a real OS permission prompt, notification delivery/banner display, Focus behavior, cold-launch delivery routing or login approval. Those native qualification gates remain separate. No full native suite or accessibility certification is claimed.
