> Historical revision 0.8 reference. Preserve feature detail, but implementation scope and interaction rules are superseded by [SPEC](../SPEC.md), [design handoff](../DESIGN-HANDOFF.md), and [milestones](../MILESTONES.md), revision 0.9. In particular, staged item drafts, clearing selections on rescan, persistent plans and installer-only selection are obsolete.

# UI state contract — revision 0.8

October 22, 2026. Canonical interactive preview: `storage-companion-direct.html`. Read with the [PRD](macos-cleaner-prd.md), [technical specification](macos-cleaner-technical-spec.md) and [design contract](macos-cleaner-design-contract.md).

The Prototype state picker sits outside the app window. It is review tooling, not production navigation. Selecting a case replaces synthetic inputs; it must never be implemented as a user-facing state selector. Recovery controls inside the app express production intent, with explicitly simulated OS interactions.

## Empty and blocked states

| ID | Trigger / owning screen | Required presentation | Recovery / permitted work |
|---|---|---|---|
| SCAN-01 | No completed scan / Overview | Explain folder choice and discovery without promising savings. Capacity can be shown independently. No old findings. | Choose scan locations; notifications and Full Disk Access remain optional. History and growth have no baseline. |
| SCAN-02 | No selected locations / Locations & access | Explain why scan cannot start. All scopes unchecked. | Select a location or add a folder; enable scan only after a usable selection. Recognized browser caches are an explicit optional discovery scope. |
| SCAN-03 | Scan finishes with skipped protected locations / Overview and affected review | Coverage notice; affected findings unavailable; no total implying full coverage. | Review access or scan accessible locations. Compare growth only when completed coverage fingerprints match. |
| ACCESS-01 | Previously authorized folder loses access / Locations & access, findings and plan | Name the folder and show Needs access. Existing affected findings cannot authorize mutation. | Choose folder again through native picker, then rescan; alternatively omit it. Other locations stay usable. Never automatically escalate to Full Disk Access. |
| SCAN-04 | Cancellation, crash or interrupted scan / Overview | Mark incomplete observations; no completed baseline or executable plan from that scan. | Start a new scan. Do not label partial counts a complete result. Preview cancellation lands in this state. |
| SCAN-05 | Selected volume is unavailable / Locations & access | Identify disconnected location. Its previous allocation is unavailable for the current scan. | Reconnect and check, or omit the location and establish new coverage. Do not silently substitute another volume at the same path. |
| CAP-01 | Startup-volume capacity query fails / Overview and alerts | Current reading unavailable; timestamped last reading explicitly historical. Hide quantitative meter rather than plotting zero. | Retry capacity query; retain settings and pause low-space decisions until a valid reading. No recursive scan to repair capacity polling. |
| SCAN-06 | Completed scan has no eligible findings / Overview | Neutral “No cleanup findings in this scan”; scope remains visible. No global clean bill of health. | Explore files or review scan locations. No deletion claim or pressure to expand permissions. |
| PLAN-01 | No selected actions with a usable scan / Cleanup plan | Keep all category selectors and inline item/profile choices visible. Quiet unselected summary; Review cleanup disabled. | Select a category directly. No mandatory trip to Overview or file inspection. Full empty states apply only when there is no scan or no eligible finding. |
| PLAN-02 | Findings become stale after access/file changes / plan and findings | Selection can remain visible; execution is blocked and the cause is stated. | Rescan before fresh review/approval. Never silently replace exact approved targets. |
| HIST-01 | No completed activity or cleared records / History | Explain what will appear and local retention. | Review storage. Do not invent an activity entry or claim files were deleted when records are cleared. |
| FILES-01 | Scoped search has zero matches / file browser | State the query and distinguish no matches from empty folder. Hide stale inspector details. | Clear search within the same folder; no broader scan required. |
| CACHE-01 | Protected cache location cannot be read / browser group | Size unavailable; affected group unselectable. Keep other supported groups usable. | Explain optional access choices or browser-native management. No broad permission prompt upfront. |
| CACHE-02 | Installed browser version has no tested cache rule / browser group | Version unsupported, size unavailable, no deletion action. | Browser-native management or recheck compatibility. A rescan does not invent support. |
| CACHE-03 | Profile/cache mapping is uncertain / browser group | Mapping unverified, unknown size, no action. Do not relabel unknown shared storage a validated profile. | Browser-native management; keep mixed website storage untouched. |
| CACHE-04 | No supported, accessible asset-cache groups / browser review | No eligible groups, with no zero-byte implication for unknown data. | Browser settings guidance or fresh manual scan. No request to close/quit unrelated apps. |
| CLOUD-01 | Upload incomplete or eviction safety uncertain / file browser | Explain why local copy must stay. Disable only the ineligible item. Pinned files remain excluded independently. | Re-read cloud status; offer action only after validated safety. Other eligible items can still be selected. |
| RESULT-01 | Every approved target fails revalidation / results | No actions applied, concrete skip causes, no claimed gain. | Fresh review of skipped groups. Never retry successful work or automatically resume an old approval. |

## Existing states retained

- Running browser: close-first guidance and disabled cache groups; Rescan only rechecks. A browser reopening between approval and execution yields a skipped outcome.
- Growth: no previous scan and incompatible coverage already have separate states. A newly completed selected-scope scan establishes a baseline; it cannot immediately produce a growth comparison.
- Alerts: off, permission waiting/blocked, stopped after Quit, login approval required, snoozed and threshold validation remain on Storage alerts. CAP-01 adds an unavailable-reading state without overwriting user preferences.
- Cleanup: running, cancellation of remaining work, partial success, protected cloud items, failed Trash move, recovery guidance and targeted revalidation remain in the existing flow.
- Search uses the scoped file list. Inspector content must disappear when no current result can be inspected.

## State and accounting rules

Unknown, inaccessible, unsupported, disconnected, stale and zero are distinct values. Never sum unknown bytes into a trustworthy total or silently render them as zero. An available-capacity reading has its own validity and timestamp, independent of scan completion. A scan result carries selected scopes, successful coverage, skipped reasons and completion status; the growth comparator checks compatible completed coverage.

Manual discovery scopes are independently selectable: Downloads, Documents, Developer, recognized browser caches and any added folders. A completed prototype scan reflects the chosen scopes in Overview suggestions and establishes a new baseline. Adding a scope does not grant its permissions, validate a browser version or promise executable findings.

Errors remain local to affected groups wherever possible. Interrupted scans and stale approval are broader execution barriers. Temporary read failures are recoverable; none justify root, Accessibility, Apple Account credentials or automatic permission escalation.

## Engineering acceptance

Use the IDs above as stable test/design references, not copy strings in domain logic. Native enums should carry typed reason, affected identity, last valid timestamp, coverage and allowed recovery actions. Render from those states; never infer safety from a disabled control. The executor independently revalidates each exact target immediately before mutation.

For each ID verify its initial view, primary recovery, cancellation/back navigation, unaffected operations, keyboard order, VoiceOver wording and both appearances. Test real permission revocation, unavailable volumes, browser helpers and file races in disposable fixtures; prototype behavior is not that evidence.

The preview models representative branch behavior with synthetic inputs. It does not simulate every OS failure timing, persist exact target identity across launches or implement native capacity sampling, browser detection or permission changes. These remain engineering validation requirements.

## Prototype verification

All 18 empty/blocked cases were opened and their intended state headings verified. Recovery checks covered first launch to location selection, selection enabling scan, a Downloads-only completed scan, and an eligible Chrome group reaching a populated plan while Safari access is denied. Both appearances were inspected on representative screens. This is interaction/layout verification, not evidence of native permissions or cleanup safety.

## Review routes and selection — revision 0.8

Overview recommendations open the relevant item review. The item inspector offers Quick Look and Reveal in Finder; it has no “Exclude from cleanup” action. Item checkboxes determine this plan’s membership. Protected/offline items retain their read-only reason. Persistent scope exclusions belong in settings, not in the inspector.

Item review loads a scoped draft from the current plan. “Add selected items to cleanup plan” applies the reviewed scope and opens Cleanup plan; “Update cleanup plan” permits clearing an existing scoped selection. Preserve other categories and deduplicate target IDs. Leaving via Back does not apply an unsubmitted draft. Reopening review loads the committed plan. Browser-profile review follows the same contract. Inline category refinement edits the plan directly. Only “Review cleanup” opens the final confirmation; no review entry executes cleanup.

Keep a single context-labelled Back action, stable window bounds and destination scroll restoration. Selecting or inspecting an item must never navigate. Initial startup must not populate hidden selections.
