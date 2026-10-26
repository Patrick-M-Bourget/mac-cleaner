# Milestones — full product scope preserved

Revision 0.9 · Approved October 22, 2026. Milestones sequence delivery; future scope remains stored here and in the historical detailed reference documents. No dates or release promises are implied.

| Stage | Retained features | Exit gate |
|---|---|---|
| M0 — Opportunity and native shell | Read-only investigation of local iCloud allocation; disposable cloud feasibility fixtures; SwiftUI/AppKit shell, themes, typography, stable window, accessibility foundations | Establish whether iCloud materially explains the personal storage problem; validate metadata-only scanning and report unsupported eviction conditions. Do not mutate personal cloud files during feasibility work |
| M1 — Personal cleanup vertical slice | Explicit scan scopes; metadata inventory; logical/allocated/capacity accounting; coverage/errors; Overview and item inspector; explicit Quick Look/Reveal; shared live session plan; Downloads file Select all/mixed selection; consequence confirmation; native Trash; progress/cancel; per-target results; minimal terminal scan activity and completed cleanup history; durable operation journal and startup recovery; clear completed history; guarded reset | Useful on the user's Mac; exact targets only; no scan hydration; no automatic execution/retry; no permanent Trash fallback; stable geometry and accessible core journey. Cloud/build/browser storage may have truthful inventory and guidance, but no unvalidated action controls |
| M2 — Validated iCloud action | Local-only eviction; uploaded/pinning/conflict checks; offline/redownload explanation; cloud category selection; skip/recheck/retry | Disposable OS-version fixtures establish reliable preconditions and no synced deletion. If unsupported, retain guidance and document why; the milestone is conditional, not silently deleted |
| M3 — Validated developer/browser adapters | Xcode DerivedData; Chrome/Safari asset caches independently; profiles/shared groups; running-helper detection; protected data sentinels; regrowth consequences; permanent cleanup confirmation; adapter-specific partial results | Explicit mutation contract for each adapter, supported versions/roots, owner inactivity, races and recovery semantics. Homebrew cache-only inventory is narrowly implemented with pinned shell-source provenance and an explicit cache override; full vendor cleanup preview/mutation and pip cleanup remain conditional submilestones. Docker inventory only; no Docker mutation |
| M4 — Growth and richer history | Compatible completed snapshots; first/missing/cleared baseline; scope-change distinctions; folder/category growth; observation intervals; bounded retention and completed-history management | Coverage changes are not growth; no inferred writer attribution. Unresolved journals exempt from normal retention eviction. Personal recurrence assessed on later manual sessions; no mandatory seven-day background sample |
| M5 — Optional storage alerts | Threshold setting; notification opt-in; 15-minute best-effort capacity checks; wake/activation coalescing; persisted episode suppression; 5 GB recovery margin; 24-hour snooze; menu-bar lifecycle; independent Start at Login; denied/blocked/unknown states | Capacity-only checks never scan or mutate files. Off by default; Quit stops monitoring, login intent remains. Tests cover restart, recovery, permission changes and delayed/missing samples |
| M6 — Full local management and guidance | Persistent user exclusions with separately designed semantics; read-only app-managed inventory for backups/Photos/Mail/Messages/system data; native management guidance; redacted diagnostics preview/local Save; mature reset/retention controls | Exclusion creation, identity/rename behavior, scan versus recommendation effect and removal/rescan rules explicitly designed before coding. No hidden creation from deselection. Diagnostics never auto-upload. Reset preserves unresolved recovery authority |
| M7 — Functional and platform hardening | Performance budgets and million-entry fixtures; supported OS/CPU evidence; ongoing privacy/API review; display restoration, localization, VoiceOver and native usability | Included features satisfy their own safety and platform gates. Intel/universal support requires actual runtime coverage. Distribution credentials and commercial packaging are not feature prerequisites |
| M8 — Commercialization | Approved release versions; Developer ID signing, secure timestamp, Hardened Runtime/entitlement audit; release-preflight corrections; final archive privacy/dependency review; notarization/stapling/Gatekeeper; clean install/uninstall and signed manual updates | Final candidate passes distribution and installation lifecycle checks; no debug entitlements or orphaned registrations. Tracked separately in #40 and [commercialization handoff](COMMERCIALIZATION.md) |

M2/M3 feasibility work may run before M1 finishes, but M1 must not depend on an unproven adapter. M4–M6 ordering can be adjusted after personal validation without removing their requirements.

## Development priority

October 23 parity checkpoint: the [full audit](PROTOTYPE-PARITY.md) maps implemented behavior, current flow gaps and every retained future capability to GitHub issues. Connected flow decisions for #44/#46/#47/#48 and #50 are confirmed in [FLOW-LOCK](FLOW-LOCK.md); presentation/delivery Q27–Q30 are also confirmed, and the annotated visual proposal b96bb97 is user-approved for connected implementation. This does not promote M2–M6 development routes, require all roadmap milestones for M1, or restart M8. M1 delivery still needs a coherent scope → findings → category selection → confirmation → results/recovery journey, not only safe filesystem seams.

Approved October 23, 2026: feature implementation and its necessary safety/platform tests take priority over M8. Developer ID credentials, signing/notarization, release-preflight work and commercial packaging do not block ordinary feature development, local builds or fixture tests. Keep ordinary ad-hoc signing required by native UI tests. If an individual OS integration needs a specific identity, record that narrow native qualification dependency rather than imposing distribution signing on all features. M8 work resumes when commercialization is explicitly prioritized; its requirements remain preserved.

## Delivered connected feature slices

After the qualified first Downloads journey #55–#57, #58 (child of #46) delivers bounded native proof of mixed included-location/access/overlap behavior and readable compact recovery actions. #59 (child of #47) supplies the remaining structured inspector evidence and eligibility explanations. Both are qualified by [source-bound native and visual evidence](validation/connected-next.md) and reuse the approved FLOW-LOCK/prototype, rather than reopening product decisions. Original parent acceptance remains open beyond each bounded proof; no future milestone is removed or promoted by this sequence.

## Preserved later exploration (not committed delivery)

App uninstall, duplicate detection, broader browser support, ordinary-file cleanup outside Downloads, whole-folder cleanup, direct backup deletion, Docker mutation, FSEvents/incremental background scanning, automatic cleanup, treemap enhancements, account/cloud services and automatic updates remain explicit backlog ideas. They require their own product/safety design; preserving them does not authorize their implementation. No “desired cleanup GB” field is planned: the accepted replacement is M5's low-space alert threshold.

## Feature-to-design trace

- Overview/item review/plan/confirmation/results: M1, extended by M2–M3 adapters.
- Four macro categories: Downloads in M1; cloud in M2; developer/browser in M3. All support explicit bulk selection of exact eligible targets when available.
- What grew: M4. History starts in M1 and gains compatible-snapshot comparisons in M4.
- Locations & access: M1. Full Disk Access remains optional contextual expansion; no root privileges.
- Storage alerts/menu bar/login: M5. The full navigation is preserved in the roadmap preview.
- Exclusions, diagnostics and expanded app-managed inventory: M6. Fixed safety protections apply from M1.
- Light/dark glass-style native UI, stable window and keyboard/accessibility: begin in M0/M1, acceptance on every milestone.

Detailed future behavior remains in [PRD](reference/macos-cleaner-prd.md), [technical spec](reference/macos-cleaner-technical-spec.md), [state matrix](reference/macos-cleaner-ui-state-matrix.md), and [layout contract](reference/macos-cleaner-layout-contract.md). Apply current SPEC/design rules whenever older text conflicts.

## Recovery, Results and access checkpoint — #60/#61/#63

The approved connected journey now includes caller-aware manual recovery, retained History disclosure/viewport context, truthful terminal outcome summaries, safe unresolved recovery routing, and restrained optional folder-access education. Shared Light/Dark components and original initial/minimum captures remain aligned with the approved flow lock. [Qualification](validation/recovery-results.md) records actual red → green, 5/5 terminal tests, 2/2 History maintenance tests and 8/8 affected regressions. Synthetic outcome presentation remains separate from Core executor fixtures and real OS qualification. Full parent issues and all future milestones stay open; #62 Local records is qualified at the checkpoint below, and M8 remains deferred.


## Shared Local records checkpoint — #62

Final app source `dadc0c1` shares maintenance from History and Locations, preserves actual caller/disclosure/viewport/live-choice context, checks fresh protected journal facts and returns recovery to management. Diagnostics remains M6-gated and returns directly to its root caller; the frozen preview and viewport survive window reopening. Shared design-system controls/Gallery and SPEC/handoff/parity are synchronized. [Qualification](validation/local-records.md) records 16/16 final scoped UI checks, earlier Overview diagnostics2/2, separate Standards/Spec reviews and67 individually reviewed originals. Actual initial captures are display-clamped1024×640; minimum900×640. Combined focused proof is not universal OS/CPU/provider/accessibility certification. No new filesystem authority or future milestone is promoted; M8 remains deferred.

The user-locked #49 capacity-refresh slice is implemented under [CAPACITY-REFRESH.md](CAPACITY-REFRESH.md), preserving Q1–Q30 and all future milestones. Shared current evidence, lifecycle/manual/scan/recheck/cleanup refresh, stale/unavailable/partial states, timeout/coalescing and stable native controls have [bounded combined qualification](validation/capacity-refresh.md) at final presentation source `8869b38`; all 71 final original captures have been individually reviewed and accepted. This is an M1 display repair, not M5 polling/permissions or M8 commercialization. #53 shell/appearance is implemented at `c5886e8` with [bounded qualification](validation/shell-appearance.md) under SHELL-APPEARANCE.md; #51 is implemented under HISTORY-ACTIVITY.md with [bounded qualification](validation/history-activity.md); #52 is implemented and qualified within [WHAT-GREW](WHAT-GREW.md) / [evidence](validation/what-grew.md) atfb20196, while still M4-gated. #54 protected release-archive guidance is implemented at62bcf8a under [RELEASE-ARCHIVES](RELEASE-ARCHIVES.md), with [bounded qualification](validation/release-archives.md); broader #31 and M6/M8 gates remain unchanged.


## Shell and appearance lock — October 24

#53 shell/appearance Q1–Q13 is locked in [SHELL-APPEARANCE](SHELL-APPEARANCE.md) and is implemented at `c5886e8`, with [source-bound native qualification](validation/shell-appearance.md). It does not promote gated M5 monitoring or alter M8 priorities; other unresolved parity decisions remain preserved.


## History activity lock — October 24

#51 Q1–Q15 and the consolidated contract are user-confirmed in [HISTORY-ACTIVITY](HISTORY-ACTIVITY.md). M1 History gains minimal terminal scan activity alongside completed cleanup runs, with All/Scans/Cleanups filters and honest scope/outcome/retention/availability. Detailed growth collection/comparisons stay M4-gated; historical routes never restore live findings or approval. Scan activity and enabled aggregates share the existing250 MB archive budget; cleanup retains its separate250 MB completed-payload budget, with protected recovery exemptions. Implemented at app source `f062ca6` with [bounded source/native qualification](validation/history-activity.md), including96 individually accepted final originals. The full future roadmap and deferred M8 remain unchanged.

#27 bounded settings is implemented under [STORAGE-ALERTS](STORAGE-ALERTS.md), with [focused qualification](validation/storage-alerts-settings.md). Shared capacity/permission/threshold presentation does not promote M5 or complete #28/#29. Genuine notification authorization/delivery remains a separate acceptance gate; M8 remains deferred.

#18/#19 Chrome contract is locked under [CHROME-CLEANUP](CHROME-CLEANUP.md). Remaining Stable/ownership/protection qualification proceeds under #18; no production cleanup or broader browser support is promoted. GPU/code caches, other browsers/versions and full feature scope remain retained.

Historical ownership investigation: [decision/evidence](validation/chrome-stable-qualification.md) did not establish the former exclusive-lease guarantee. The revision below supersedes that prerequisite; all browser features remain preserved.

## Chrome native close-and-clean revision — October25

The user approved revised [CHROME-CLEANUP](CHROME-CLEANUP.md) rules5–7. Chrome-only approval is a verified profile/asset-cache group with refreshed estimates, not a frozen inode manifest. Require browser/helpers closed, revalidate verified scope/ownership/layout with no-follow access, reject replaced directories/unknown evidence, stop unstarted work on detected activity/conflicts and report partial outcomes. Ordinary-use residual races are explicit; an exclusive external lease is no longer prerequisite. Newly generated eligible entries inside the same approved cache group may be included; new profiles/groups stay unchecked. Downloads and all personal files retain exact-target protections. Earlier exclusive-lease stop-rule text is historical and superseded only for this Chrome model. This is the approved qualification contract; the production allowlist remains empty until #19 passes. Extension-based cleanup remains a possible later alternative, not this slice.



## Chrome #18 final capability checkpoint

Remaining #18 qualification is complete within the [recorded compatibility boundary](validation/chrome-close-clean.md#final-saved-record-evidence-and-18-capability-decision): actual Stable156.0.8078.48/macOS26.6.2 arm64; standard split-root removal/regrowth and native conflict/access checks at8f610f7; genuine headed password fill, saved-address record retention and download history atfa8192d; earlier27c1db6 preserves two-profile site/session/history/offline semantics. That capability decision enabled the subsequent #19 browser/profile → shared plan → permanent confirmation/results implementation. At the #18 checkpoint, production cleanup remained disabled pending #19. The qualified #19 delivery is recorded below. Unknown/shared/managed/redirected layouts remain unavailable; additional compatibility remains future scope. Address form-suggestion acceptance is unqualified; actual saved-record preservation is independently proven. Personal-file/Downloads exact-target protections are unchanged.


## Chrome #19 qualified delivery

The approved browser/profile → shared plan → consequence-specific confirmation → per-group results/History journey is implemented and qualified through PR72. The [source-bound report](validation/chrome-cleanup.md) records the unchanged production Swift adapter’s full genuine Chrome pass, 11 distinct scoped public UI methods and 47 individually reviewed originals. This delivers one bounded M3 adapter; it does not complete all M3, enable Safari/GPU/code caches or expand Downloads/personal-file authority. All retained future features and M8 deferral remain unchanged.


## Xcode #16/#17 scope refinement — confirmation pending

The user confirmed Q1–Q7 in [XCODE-CLEANUP](XCODE-CLEANUP.md). Initial cleanup is limited to verified project-specific generated build intermediates under explicitly enabled standard DerivedData, with project/file refinement and exact frozen approvals. Source, archives, dSYMs, products, package checkouts, indexes and module caches stay protected from this initial action. Additional generated-data categories and custom build roots are retained M3 future scope requiring separate qualification; they have not been removed from the roadmap. #16’s remaining qualification precedes #17’s full app journey. Final contract confirmation is pending; no capability or M8 work is enabled by this scope record.
