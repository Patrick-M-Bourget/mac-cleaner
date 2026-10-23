# Native keyboard cancellation and focus — #35

Focused qualification passed October 23, 2026. Source **b4b60f61eaf5b493a8337c5fc75e44c5efa440a9**; [hosted run 40007882114](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40007882114), manual `keyboard` suite. The native journey passed **1/1**, zero failures/skips, **40.735 seconds**. This is a bounded addition to earlier evidence, not a new full-suite run or completion of #35.

## Environment and provenance

The result bundle reports Apple Virtual Machine 1, arm64, macOS **26.6.2 (25G83)**. Build/test logs identify **Xcode 26.6 (17F113)** and macOS26.5 SDK. Debug test override binds a newly created, test-owned `StillSelectionUI-UUID` directory as the Downloads fixture. The sole file contains 137 fixed bytes; no personal folder is scanned or changed, and no cleanup is approved. No OS keyboard/accessibility preferences, permissions or credentials are changed.

GitHub artifact `native-test-results`: ID **12525480945**, 110289 bytes, archive digest `sha256:601df5d2be9f3dbdcf334bc0e857b7353eb4a5fc4f4a4496ee9555882fe39dac`. The run uploads the original xcresult; its summary records one passed test, no runtime warnings. Local Xcode27.1 build-for-testing also passed before dispatch; local build success is separate from hosted runtime evidence.

## Public behavior exercised

`WorkspaceUITests/testKeyboardCancelRestoresReviewFocusWithoutChangingSelection`:

1. Explicit native picker and pointer selection establish one disposable exact target.
2. Command-1 then Command-2 navigates Overview/plan while retaining the selected item.
3. Review opens the consequence sheet with Move to Trash reachable. Escape dismisses before execution.
4. The selected count, checked category, exact window frame and original file bytes remain unchanged.
5. Return, without clicking or tabbing, reopens review through its restored native focus. Escape then Space repeats that behavior; final Escape preserves the selection and original bytes.

The existing native review control and Cancel shortcut passed without application changes. There was no proven product defect and no speculative UI change; no new visual states or screenshot replacements were introduced. The focused test is included in ordinary all-suite runs, while the manual `keyboard` suite skips unrelated package tests and executes this journey alone.

## Remaining gates

Picker and initial selection setup use pointer controls. This proves the stated menu navigation, Escape, restored Review focus, Return/Space and stable frame behavior; it is **not a complete keyboard-only workflow**. Full keyboard picker/inspection/selection, confirmation approval, Stop/results/retry, focus traversal and window recovery still require broader native qualification. No VoiceOver, localized text, contrast/motion/transparency preference, macOS14 or Intel qualification is claimed. No production keyboard shortcut or destructive default action was added. [Release qualification](release-qualification.md) remains incomplete.
