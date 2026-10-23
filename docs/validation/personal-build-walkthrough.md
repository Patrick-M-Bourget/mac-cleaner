# Personal-build walkthrough — #14 handoff

**Pending user-run validation.** Prepared from92521d7; no new personal folder was scanned and no personal file was moved by this handoff. #13 completed-history/reset and remaining #34 qualification gates are open. This is a local development build, not a notarized release. The local host is macOS27.0.1/arm64; the target14.0 setting is not tested minimum-OS support, and the measured host volume is245GB rather than the originally described512GB Mac.

## Open the personal build

From the repository root, build with ordinary local ad-hoc signing (no account, distribution certificate or changed global Xcode setting):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project Still/Still.xcodeproj -scheme Still -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/personal
open .build/personal/Build/Products/Debug/Still.app
```

The prepared artifact is at `.build/personal/Build/Products/Debug/Still.app` in the issue-14 worktree; generated files are not committed. Local Debug build succeeded; `codesign --verify --deep --strict` passed and signature inspection reported ad-hoc/arm64 with no TeamIdentifier. It was not launched by this preparation. This satisfies a local development-artifact prerequisite, not Developer ID, Hardened Runtime or notarized-distribution qualification. Rebuild from the final integrated commit before treating it as a current candidate. Keep other copies of Still closed so the selected app and commit are unambiguous. Launch with no `--future-milestones`, `--ui-test-*` or `--design-*` flags and no `STILL_TEST_*` environment overrides. No script changes Gatekeeper/trust settings or asks for broad grants. If normal local launch fails, record the error and stop rather than disabling OS protections.

Launch reads startup-volume capacity and existing local recovery records. It does not automatically select or enumerate personal folders. Existing interrupted records may open read-only recovery first; keep that evidence and use Return to Overview. Opening the app is not approval to retry a prior cleanup. Ordinary operation uses local Application Support/Still, so do not erase that directory to get a blank screen.

## 1. Inspect a useful, bounded location — read-only

Choose **Choose folder…** on Overview and select one small location you recognize. Start with an ordinary local folder before a large Downloads or cloud tree. The chooser grants that selected scope; no Full Disk Access is required for this walkthrough. If denied/revoked/unavailable, record the affected scope and recovery text; another explicitly selected folder should remain useful. Do not expand access merely to eliminate an Unknown.

Record scope type (without private filenames), complete/partial coverage, observation time, logical bytes, allocated bytes, selected-volume metric and startup-volume available capacity. These are different measurements. Entry limits/protected packages/inaccessible children mean some totals remain Unknown; a known subtotal does not establish a whole-Mac total. Use Stop scan if needed; it prevents further work at returning metadata boundaries, not a forced termination of a blocked provider call.

## 2. Assess iCloud opportunity — read-only

In a deliberately selected iCloud location, read **iCloud in this scan**: downloaded local allocation, cloud-only logical size and unknown state/pinning. Metadata inventory never requests contents, thumbnails, hashes or eviction; this does not independently certify provider non-hydration. Avoid Quick Look during this assessment: it is a separate explicit content-preview action available only for fresh positive local evidence.

Existing [consented partial assessment](cloud-inventory.md) found9,343 cloud-only identities and no positively local downloaded allocation in a10,000-entry bounded subset. That is not a whole-folder zero claim, and cloud logical bytes are not potential savings. No repeat or larger scan is required just to reproduce that record. Choose narrower scopes only when useful and explicitly intended. Local cloud eviction remains unavailable.

## 3. Review Downloads choices without changing files

Explicitly choose the real configured Downloads root or a nested folder inside it. An unrelated folder merely named Downloads is not eligible. File names inspect; checkboxes select. Try one ordinary local file you understand, navigate to Cleanup plan and back, and verify the same choice survives. View cleanup plan navigates only. Select all applies to exact eligible files, including eligible nested files; it does not select directories/packages/symlinks/managed libraries/cloud items or future discoveries.

Open **Review cleanup**, expand **Exact files** using its disclosure arrow and check the actual paths/count/action. Cancel must preserve choices and return focus without resizing the window. This is the stopping point for the read-only personal walkthrough. Deselect any exploratory choices afterward if they are not intended for cleanup.

## 4. Optional deliberately approved cleanup

**Do not proceed without the user's explicit approval of the concrete exact-file batch.** Record that approval locally immediately before the final Move to Trash confirmation; this document is not approval. Start with the smallest useful reviewed batch. Never use personal data to test substitutions, crashes, failures, cancellation races or recovery corruption; [executor](downloads-executor.md), [cancel/retry](cancel-retry.md), [refresh](refresh.md) and [recovery](startup-recovery.md) evidence already use owned disposable fixtures.

Re-read expanded paths and consequences. Move to Trash has no permanent fallback and does not free Trash-held space. Results must separate each success/failure/skip/cancelled/unknown outcome, planned logical size, planned allocated bytes held in Trash and independently observed startup-volume capacity change. Capacity may move for unrelated reasons or APFS sharing/snapshots. Reveal in Trash uses only a returned location; restoration/folder structure is not guaranteed. Do not empty Trash as part of this validation.

Stop after current file stops new operations, not an underway native call. The general plan is consumed. **Recheck unfinished files** only scans fresh evidence; unchanged eligible unfinished files need a new review/final approval. Completed successes and new discoveries stay excluded. Unknown outcomes remain evidence to inspect, never assumed success or automatic retry.

## 5. Quick native usability check

Use Light then Dark, initial then minimum window size. With keyboard navigation, traverse Overview → selected item → plan → consequence sheet → Cancel; verify visible focus, checkbox Space behavior and unchanged bounds. Close/reopen the window using Window → Show Still while a plan is pending; explicit Quit ends the session plan. Do not simulate a crash during personal cleanup. VoiceOver/localization/increased contrast/reduced motion/transparency/multi-display qualification remains separately pending; record any observed issue rather than treating this quick check as certification.

History/reset may be inspected after #13 integrates and its gate passes; do not use Clear/Reset against valuable unresolved evidence during this handoff.

## 6. Record usefulness, then revisit manually

Keep detailed paths/approvals/screenshots locally; commit only path-free aggregate results with consent. Fill this record rather than copying sample values:

```text
Candidate commit / build date / OS + CPU:
Scope types and observation times:
Coverage / unknown or excluded boundaries:
Logical / allocated totals (or Unknown):
iCloud local allocation / cloud-only logical subtotal / unobserved remainder:
Useful opportunities found; was the original storage problem explained?:
Personal exact-batch approval recorded? (no / local reference):
Actual per-target outcome counts (if approved):
Planned bytes held in Trash / observed capacity before+after and metric:
Keyboard / focus / appearance / window findings:
Remaining problems and next useful investigation:
Later manual session date / recurrence observation:
```

No timer/background sampling is needed for recurrence: reopen during a later ordinary session and inspect the same explicitly selected scope if useful. Low available space alone is not evidence the app failed; Trash, snapshots and other processes can dominate. #14 remains open until the user-run evidence establishes practical usefulness and any personal cleanup has a concrete approval record. [Release preparation](release-qualification.md) remains a separate gate.
