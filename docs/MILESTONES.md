# Milestones — full product scope preserved

Revision 0.9 · Approved October 22, 2026. Milestones sequence delivery; future scope remains stored here and in the historical detailed reference documents. No dates or release promises are implied.

| Stage | Retained features | Exit gate |
|---|---|---|
| M0 — Opportunity and native shell | Read-only investigation of local iCloud allocation; disposable cloud feasibility fixtures; SwiftUI/AppKit shell, themes, typography, stable window, accessibility foundations | Establish whether iCloud materially explains the personal storage problem; validate metadata-only scanning and report unsupported eviction conditions. Do not mutate personal cloud files during feasibility work |
| M1 — Personal cleanup vertical slice | Explicit scan scopes; metadata inventory; logical/allocated/capacity accounting; coverage/errors; Overview and item inspector; explicit Quick Look/Reveal; shared live session plan; Downloads file Select all/mixed selection; consequence confirmation; native Trash; progress/cancel; per-target results; completed history; durable operation journal and startup recovery; clear completed history; guarded reset | Useful on the user's Mac; exact targets only; no scan hydration; no automatic execution/retry; no permanent Trash fallback; stable geometry and accessible core journey. Cloud/build/browser storage may have truthful inventory and guidance, but no unvalidated action controls |
| M2 — Validated iCloud action | Local-only eviction; uploaded/pinning/conflict checks; offline/redownload explanation; cloud category selection; skip/recheck/retry | Disposable OS-version fixtures establish reliable preconditions and no synced deletion. If unsupported, retain guidance and document why; the milestone is conditional, not silently deleted |
| M3 — Validated developer/browser adapters | Xcode DerivedData; Chrome/Safari asset caches independently; profiles/shared groups; running-helper detection; protected data sentinels; regrowth consequences; permanent cleanup confirmation; adapter-specific partial results | Explicit mutation contract for each adapter, supported versions/roots, owner inactivity, races and recovery semantics. Homebrew preview/cleanup and pip inventory/cleanup are retained conditional submilestones. Docker inventory only; no Docker mutation |
| M4 — Growth and richer history | Compatible completed snapshots; first/missing/cleared baseline; scope-change distinctions; folder/category growth; observation intervals; bounded retention and completed-history management | Coverage changes are not growth; no inferred writer attribution. Unresolved journals exempt from normal retention eviction. Personal recurrence assessed on later manual sessions; no mandatory seven-day background sample |
| M5 — Optional storage alerts | Threshold setting; notification opt-in; 15-minute best-effort capacity checks; wake/activation coalescing; persisted episode suppression; 5 GB recovery margin; 24-hour snooze; menu-bar lifecycle; independent Start at Login; denied/blocked/unknown states | Capacity-only checks never scan or mutate files. Off by default; Quit stops monitoring, login intent remains. Tests cover restart, recovery, permission changes and delayed/missing samples |
| M6 — Full local management and guidance | Persistent user exclusions with separately designed semantics; read-only app-managed inventory for backups/Photos/Mail/Messages/system data; native management guidance; redacted diagnostics preview/local Save; mature reset/retention controls | Exclusion creation, identity/rename behavior, scan versus recommendation effect and removal/rescan rules explicitly designed before coding. No hidden creation from deselection. Diagnostics never auto-upload. Reset preserves unresolved recovery authority |
| M7 — Release hardening | Performance budgets and million-entry fixtures; supported OS/CPU matrix; privacy/API audit; display restoration, localization, VoiceOver; Developer ID signing/notarization; clean install/uninstall; manual signed updates initially | Current platform requirements verified, supported adapters documented, no debug entitlements or orphaned background items. Intel/universal release requires actual test coverage |

M2/M3 feasibility work may run before M1 finishes, but M1 must not depend on an unproven adapter. M4–M6 ordering can be adjusted after personal validation without removing their requirements.

## Preserved later exploration (not committed delivery)

App uninstall, duplicate detection, broader browser support, whole-folder cleanup, direct backup deletion, Docker mutation, FSEvents/incremental background scanning, automatic cleanup, treemap enhancements, account/cloud services and automatic updates remain explicit backlog ideas. They require their own product/safety design; preserving them does not authorize their implementation. No “desired cleanup GB” field is planned: the accepted replacement is M5's low-space alert threshold.

## Feature-to-design trace

- Overview/item review/plan/confirmation/results: M1, extended by M2–M3 adapters.
- Four macro categories: Downloads in M1; cloud in M2; developer/browser in M3. All support explicit bulk selection of exact eligible targets when available.
- What grew: M4. History starts in M1 and gains compatible-snapshot comparisons in M4.
- Locations & access: M1. Full Disk Access remains optional contextual expansion; no root privileges.
- Storage alerts/menu bar/login: M5. The full navigation is preserved in the roadmap preview.
- Exclusions, diagnostics and expanded app-managed inventory: M6. Fixed safety protections apply from M1.
- Light/dark glass-style native UI, stable window and keyboard/accessibility: begin in M0/M1, acceptance on every milestone.

Detailed future behavior remains in [PRD](reference/macos-cleaner-prd.md), [technical spec](reference/macos-cleaner-technical-spec.md), [state matrix](reference/macos-cleaner-ui-state-matrix.md), and [layout contract](reference/macos-cleaner-layout-contract.md). Apply current SPEC/design rules whenever older text conflicts.
