# Startup capacity refresh — #49 locked contract

User-confirmed October24,2026, grilling Q1–Q12 and final consolidated confirmation. Parity O02/O06/X02. This contract extends the approved Q1–Q30 connected flows without reopening them. It is approved for implementation, not yet native-qualified. All future milestones remain preserved; no M5 polling or M8 work is added.

## Triggers and ownership

One process-owned current startup-volume capacity state serves Overview and sidebar. Request at launch, alert-open, and once when a whole logical manual scan finishes/stops/fails or a cleanup attempt ends, regardless of outcome. Foreground activation requests only when the last successful reading is at least30seconds old, no successful reading exists, or the latest attempt failed. Manual Refresh capacity/Try again and terminal scan/cleanup triggers always request a fresh read. No timer while idle, recursive scan, grant request, background keepalive or automatic retry loop. State survives window close/reopen only while the process remains alive; Quit does not persist this transient reading. Window recreation itself does not duplicate a successful launch read.

Read startup `/` capacity independently of selected-scope scans, including external drives. Prefer macOS available-for-important-usage, with explicitly labelled available-capacity fallback. Current display reads never enable alerts, request notification permission or change episodes/snooze; existing optional alert policy remains independent. Alert-open's historical checked-at context stays separate from current capacity.

## Concurrency and timeout

Coalesce overlapping demands. A post-action request must receive a read started after that terminal action: an already-running pre-action read cannot satisfy it. Preserve one trailing fresh demand when needed. Older/expired request completions cannot overwrite accepted newer state. Each logical request expires after10seconds; ignore a later result and show failure/retry. Expiry stops refreshing; it does not promise to forcibly interrupt a synchronous OS metadata call. No timeout blocks scan, selection, execution Results or navigation.

## Evidence and presentation

Use existing VolumeSummary/CapacityMeter, shared tokens and quiet native secondary actions. Overview keeps its approved capacity → coverage → findings hierarchy; Refresh capacity belongs inside the capacity card and is separate from Scan again. Sidebar shows the same current evidence/status and does not acquire a duplicate primary action. Disable only the refresh/retry control while pending. Retain prior successful values during refresh with subtle Refreshing… text; initial state is Checking capacity… with no fabricated amount. Reserve stable status/action space, no layout animation, destination/window resizing or scrolling jumps. Supply accessible status text and full native action labels.

A failed/expired read with previous valid evidence shows Last observed <time>, Couldn't refresh capacity and Try again. With no successful available reading show Capacity unavailable, no filled meter, and Try again. The last-success state is explicitly stale after failure; do not silently call it current. Attempt time is separate from successful observation time. Never invent zero or reset success time on failure. A valid available value with missing/unusable total remains usable: show the amount, Total capacity unavailable and no meter. Negative/non-finite/invalid available values, or available exceeding an otherwise valid total, are failure; zero available is legitimate evidence. Missing/invalid total alone must not invalidate a valid available amount. A successful read clears prior failure. Disclose observation time and actual important/fallback metric in secondary text; unknown volume identity never licenses cross-volume comparison.

Operation Results/History retain independently recorded before/after observations unchanged. Current refresh cannot rewrite those records, change estimates, attribute every observed capacity difference to cleanup or promise savings. Do not calculate deltas across incompatible metric/volume observations. No automatic publication of scope/external-volume readings into startup capacity.

## State and native acceptance

Meaningful shared Gallery examples: checking, refreshing with retained evidence, observed important/fallback, valid available/unknown total, stale-after-failure, unavailable-without-history. Use inert labelled examples; do not put a scenario chooser in production. All Light/Dark initial/minimum changed-state originals must be reviewed with stable window/footer and action reachability before UI integration. Keep current findings/choices/caller context intact during every display refresh.

User explicitly approved the public capacity-refresh service boundary with controlled readings/time on October24; existing public UI journey seam remains approved. Verify trigger cadence, coalescing/trailing demand, expiry/late replies, failure recovery, partial metadata and independent historical/alert data. These tests do not certify every macOS filesystem/volume/permission or OS/CPU. Record actual red→green and source-bound visual/regression evidence in validation/capacity-refresh.md before closing#49.
