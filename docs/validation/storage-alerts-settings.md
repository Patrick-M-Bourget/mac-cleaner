# Storage alerts settings #27 — bounded implementation evidence

Contract [STORAGE-ALERTS](../STORAGE-ALERTS.md), Q1–Q7. Locked October25,2026. Live/controller source `336fcb9`; final Gallery `5049ce4`. Bounded settings qualification complete; genuine OS authorization/delivery remains open.

## Public-boundary checks

- First public applied/pending controller red: missing applied/draft evidence. Minimal green: edits do not become active on enable; only explicit Apply changes the saved/applied threshold. Logs /tmp/alerts27-red.log and /tmp/alerts27-green1.log.
- Actual stale permission behavioral red: an earlier denied response overwrote a newer allowed response (/tmp/alerts27-permission-red.log). Generation-guarded completion preserves the newer status; no prompt is added to read-only refresh.
- Full StorageAlerts package47/47 passes at336fcb9 (/tmp/alerts27-package-final.log). This includes existing monitoring/delivery/suppression/lifecycle/persistence tests; no actual OS delivery is inferred.
- Local Xcode27.1 build-for-testing passes (/tmp/alerts27-build-final.log).
- Native actual missing-capacity red40236832300 atcafebe4: both methods fail at StorageAlertsUITests.swift:21, “Settings must expose shared current capacity.” Focused settings run40237105719 at336fcb9 passes2/2 (88.923s/76.547s), initial/minimum with both themes: capacity, applied/pending, unavailable total, denied permission/Settings failure, quiet explanation, Gallery and Plan/Overview returns with fixed outer bounds.
- Independent Spec review: no actionable findings. Standards: no blockers, one missing known-total invalid-draft visual example corrected by the one-line Gallery addition in5049ce4; four focused original captures accepted. Root reviewed that narrow follow-up; live production/controller source remains336fcb9.

## Native and visual review

Settings [40237105719](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40237105719) passes2/2 at336fcb9. Known-total invalid Gallery [40237302793](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40237302793) passes2/2 at5049ce4 (27.042s/22.316s). Existing alerts [40237331826](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40237331826) passes3/3 at5049ce4: hidden-by-default/no-entry-prompt, on-demand window-close/read-only login, and disposable opt-in refusal (12.594s/15.172s/6.303s). Longer-page tests reveal existing controls before acting; assertions are preserved. These are seven methods across separate focused runs, not a whole-suite pass.

All29 originals individually accepted:24 settings/live/Gallery,4 known-total invalid Gallery,1 old disposable refusal. [Per-image review, original manifests and source reviews](../visual/storage-alerts-settings/REVIEW.md) retain exact viewport/source limits. No real OS grant, Settings change or notification was used by those fixtures.

## Genuine OS gate remains open

#27 requires genuine macOS notification authorization AND delivery before closure. Existing [native harness](../../Validation/AlertsNative/README.md) explicitly does not certify delivery even if its authorization/lifecycle journey passes. Last real attempt40018074926 was inconclusive: no attributable actionable Still permission prompt was observed, so it stopped unsupported. Neither a skip, controlled authorization fixture nor OS request acceptance proves visible delivery. No unchanged repeat attempt or new personal-host permission operation is part of this slice.

The settings changes can be qualified and integrated while #27 remains open for this criterion. M5 stays development-gated; #28/#29 remain separate and blocked as recorded. #49 shared display freshness and #53 shell behavior are preserved. All future milestones and deferred M8 remain.

## Review build

Local Xcode27.1 arm64/ad-hoc review app: `/Users/bender/Library/Caches/Codex/mac-cleaner-implementation/artifacts/alerts-settings-5049ce4/Still.app`, BUILD.md alongside. Deep/strict signature verification passes; executable SHA256 `4c1d9ab01d12e05a8e123dd793ecd27ce5a27d69108b0f44a58394a20373c03a`. Explicit `--future-milestones` reveals Storage alerts; ordinary launch keeps the existing gate. This is not a notarized/commercial release.

## Integration

MergedPR68 at `97a98f8`. Live/controller remains336fcb9, final Gallery5049ce4; later changes are documentation. #27 stays open for genuine OS authorization/delivery. Temporary branch/worktree retired after clean/merged verification; full future milestones and other issue gates retained.
