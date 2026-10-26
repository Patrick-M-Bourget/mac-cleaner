# Chrome cleanup native visual review

The [capture index](manifest.json) preserves 47 selected, unchanged PNG originals with source/run, test name, dimensions and SHA256. Each was inspected individually by root or the delegated visual reviewer. The per-run original XCTest export manifests are retained; those manifests can name additional attachments that are available only in the full workflow artifact. This is a selected visual evidence set, not a complete export of all intermediate runs.

| Original set | Source / run | Review |
|---|---|---|
| Browser review, mixed plan, confirmation, mixed results and Chrome-only results: 24 | `345d723` / 40266115536 | Initial 1024×640 and minimum 900×640, Light/Dark. Shared white/near-black reading planes, native chrome, orange Downloads/teal browser identity, selection summary, separate consequences and fixed actions are coherent. |
| Unavailable/empty states: 8; rescan with a newly discovered group: 2 | `fe83162` / 40265139115 | Actual corresponding methods pass, although the overall workflow fails other checks. Unsupported, denied and unknown never look like verified empty. Empty alone displays a known zero and disabled group. Prior selection remains checked; the new profile remains unchecked. |
| Inert shared gallery: 8 | `802ad2d` / 40265922104 | Both themes/sizes, upper protection/permanence notices and lower group states. Unknown sizes remain unknown; disabled rows retain their specific reason. These are presentation fixtures, not real OS failure evidence. |
| Cancelled Chrome stage: 1 | `ff5d928` / 40266203098 | Recorded Downloads success and separate Chrome cancellation remain distinct. No window/footer displacement. |
| Final Chrome-only toolbar context: 4 | `ceec55f` / 40266856314 | Both sizes/themes show “Cleanup results · individual outcomes”, complete permanent cache outcome and independent capacity evidence. No phantom Trash success. |

## Viewport limits

Browser/plan pages scroll under a fixed footer. Rows partly outside the viewport are not treated as missing or visually certified from a clipped fragment. The 640×520 consequence-specific confirmation fits entirely in both tested windows; Cancel and Run cleanup remain visible.

Mixed result captures show the Downloads outcome followed by the separate Chrome heading/profile/status. Their lower removed-count/permanence/capacity paragraphs remain below the captured viewport. Some nominal Dark “top” captures retain the preceding lower scroll position; they do not prove a visible top heading. The complete, identical shared ChromeResultsSection is visible in Chrome-only captures, including permanent removed-file/byte counts, no Trash recovery or Undo, regrowth and independent capacity caveats. Public mixed journeys separately verify the real cache removal and protected sentinels. We do not infer offscreen layout from pixels.

The cancellation PNG similarly clips its zero-removal line. The public native assertion reads the actual text value and checks the untouched cache leaf; that is functional evidence, not a visual zero-count claim.

## Scope

The approved prototype supplies the visual direction; current SPEC/handoff and shared native design system govern real states and qualified compatibility. No prototype sample sizes, scenario controls, personal account labels or automatic selections are copied into production. These captures do not certify all macOS versions, accessibility configurations, localizations or browser compatibility. [Functional/native qualification](../../validation/chrome-cleanup.md) records source-separated results and remaining gates.
