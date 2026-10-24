# History activity — #51 locked contract

User-confirmed October 24, 2026, Q1–Q15 and consolidated lock. Parity H01–H04. Approved for implementation; native qualification is pending. This extends the existing History, Local records and growth contracts without changing cleanup authority or promoting M4–M8.

## Purpose and scope

History is the local record of scans and cleanup outcomes. Normal M1 builds retain minimal scan summaries as well as existing completed cleanup runs. Growth comparisons, detailed growth-baseline collection and What grew remain under the existing M4 gate. No duplicate history store, raw scanned-file catalogue, persisted selection, restored approval or historical executable draft is introduced.

Default to one newest-first All activity feed, with Scans and Cleanups filters. Distinguish record type and outcome with native text/symbols. Expand recorded details inline. Preserve existing cleanup facts, per-file results, legacy timestamp explanations and independently recorded capacity measurements; terminal failed/skipped/cancelled cleanup facts are not represented as successful cleanup. Unfinished cleanup remains in protected Recovery rather than completed History.

## Scan operation and durable summary

One actual user-initiated Scan, Scan again or Recheck produces at most one terminal activity record, grouping all locations requested by that operation. Internal consistency attempts remain in that record. A cancelled picker, viewing a record or refreshing volume capacity produces no scan activity. Current progress stays in the existing toolbar; do not persist pending scan entries or add a scan-recovery journal.

Record complete, partial, stopped and failed terminal outcomes honestly. A crash or Quit before a finalized summary is saved can leave no entry; never infer completion or automatically resume. Root locations not attempted after stopping/failure remain distinguishable from observed locations. Unknown or incomplete totals stay unknown/qualified, not zero or complete. Retain location-specific coverage and actual observation times. Order scan activity by its finalized observation/completion time; retain existing cleanup outcome-date behavior. Never claim scan bytes are reclaimable or released space. Avoid summing overlapping locations twice; use the canonical observation accounting or show separate location measurements when a valid combined total is unavailable.

The compact local summary contains identity, time, requested root labels/paths, terminal outcome, coverage and supported aggregate counts/logical/allocated measurements. Root paths distinguish identically named selected folders and appear in expanded details. Persist no scanned child-file list, file contents, per-file scan paths, live checkboxes or cleanup authority. Persist bounded reason categories/counts rather than raw per-file error descriptions. Historical paths describe the recorded scope, not current permission, coverage, identity or existence; opening details does not resolve access or enumerate files.

An invalid/oversized summary or failed persistence cannot block an otherwise usable scan. Preserve current results and live choices and show a nonblocking explanation that this activity could not be saved. Do not fabricate a saved row, queue background replay, retry automatically or rescan to repair history. Later independent explicit scans attempt their own recording. Cleanup's separate durable-journal requirement remains unchanged.

## Storage and retention

Reuse the existing bounded aggregate archive and its cooperation/ownership safeguards; extend its public archive boundary rather than copying observations into an independent store. Normal mode writes only scan summaries. Detailed growth snapshots are still recorded only when the existing future feature is enabled and its complete/measured/fingerprint rules admit them. A partial/stopped/failed activity is not a comparison baseline.

Scan activity and enabled growth aggregates share one 250,000,000-byte archive budget and a 90-day age limit. At most 30 qualifying growth baselines are retained globally across locations; that count does not cap activity entries or guarantee a baseline per scope. Retain newest eligible records when the shared budget requires eviction, preserving truthful references when a linked baseline expires. Use actual encoded-size bounds; never silently truncate a summary and claim it was saved. Preserve known legacy aggregate records when extending the schema, and fail honestly on unreadable/unsupported data rather than repairing or replacing it during ordinary viewing.

Completed cleanup retains its existing separate 250,000,000-byte record-payload budget and 90-day policy, with no 30-run limit. Unfinished recovery and consumed approval identities retain their existing protections. These are retained-record limits, not a combined 250 MB app-files or physical SQLite/WAL ceiling. Preserve existing epoch/generation protection: late writes captured before Clear/Reset must not repopulate cleared history. This invalidates historical persistence only, without revoking current usable scan results or live choices on Clear.

## Clear, Reset and independent availability

Shared Local records retains the action; label it Clear completed history. Its native confirmation explicitly names scan activity, completed cleanup records and retained growth baselines, regardless of History's current filter. Original files, Trash, live selections, appearance, protected recovery facts and consumed approval identities remain unchanged. Preserve existing fresh journal/execution guards. A multi-store clear is not atomic: report partial success accurately and never claim every store cleared when a later step fails. Reset retains the #53 staged appearance outcomes and all existing fresh recovery safeguards.

Load scan and cleanup history independently. A failed store never hides readable records or becomes a false zero count. All activity shows available records with a specific incomplete-history warning; a filter whose store cannot be read shows Unavailable, not its empty state. Try again reloads history only and preserves current choices. It never scans, restores authority, changes permission, silently repairs a store or bypasses maintenance protection. Reading an unavailable cleanup journal still blocks operations that require knowledge of protected recovery facts.

## Navigation, context and empty states

History remains the root sidebar destination. Its filter, expanded activity and existing observed viewport are process-owned, retained on contextual returns/window reopening. Quit does not persist a cleanup plan or navigation state. Apply existing new-destination versus caller-return rules; filter interaction changes only History presentation and preserves app selections, theme and fixed window bounds.

When What grew is enabled, an eligible location within an activity can link to that exact retained comparison observation. Hide the route while gated. Do not pick a different observation if the linked baseline is absent/expired/incompatible. Explain unavailable comparison data without scanning. History → What grew supplies one Back to History restoring its filter, expansions and viewport; direct sidebar growth navigation retains normal root behavior. Viewing historical activity or comparisons never changes current selected scope, raw scan findings or cleanup choices. Existing History → Local records → Recovery → Local records → History caller behavior remains authoritative; add no duplicate Back loop.

Empty copy describes retained records, not whether the user has ever acted:

- All activity: No retained history.
- Scans: No recorded scans.
- Cleanups: No recorded cleanup runs.

Use brief retention guidance. Offer Go to Overview for scan-related absence and View cleanup plan for cleanup-related absence; these are explicit navigation only. All-empty can offer these two existing destinations as primary/secondary actions. Preserve the existing explicit-new-plan rule when entering Plan after terminal Results. Clear and age/budget eviction must not turn an unavailable store into an apparently successful empty history.

## Shared design and qualification

Use the approved white Light/near-black Dark shell, PageHeader, SummarySurface, native disclosure/filter controls, StatusRow, EmptyState and shared Local records entry/actions. Add shared scan-activity presentation and inert Gallery examples for complete/partial/stopped/failed, multi-location/unknown measurements, unavailable/filtered-empty and retention explanations before composing live screens. Retain the existing inline cleanup outcome presentation and recovery actions. Keep the History/What grew return route bounded and clear; no extra sidebar destination or automatic scan.

Minimum 900×640 and host-clamped initial sizing remain fixed. Filters, expansion, warning states and long recorded paths change content rather than the window. Preserve readable native titles, reachable actions, selection versus inspection distinctions and scroll anchors; use the #53 message-only accessibility ownership pattern for recovery controls. Review original Light/Dark initial/minimum captures through the user journey as well as shared Gallery states.

Existing approved public app journeys cover navigation, filtering, confirmation and recovery safeguards. The additional proposed public scan-activity archive boundary uses disposable files and controlled time for save/reload, bounded retention, Clear and availability/failure behavior; user agreement is required before writing tests there. Use actual vertical red→green. Source reviews and native original-capture review precede integration. Fixtures do not certify every macOS permission/disk failure, iCloud provider, OS/CPU or accessibility configuration. All future capabilities and deferred M8 remain preserved.

## Decision trace

Q1 combined activity; Q2 comparisons stay What grew; Q3 one operation/multiple locations; Q4 honest terminal outcomes; Q5 minimal local summaries/root paths; Q6 All/Scans/Cleanups; Q7 M1 summary versus M4 detail gate; Q8 separate bounded budgets; Q9 global Clear; Q10 exact contextual growth route; Q11 terminal-only recording/crash boundary; Q12 explicit operations versus internal attempts; Q13 nonblocking save failure; Q14 independent readable/unavailable stores; Q15 honest retained-record empties. Consolidated contract confirmed and implementation explicitly authorized.
