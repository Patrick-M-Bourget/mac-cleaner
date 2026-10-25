# Standards review — #52 Core increment

Reviewed `8f0172a...dce5c86 -- Packages/StillCore`, read-only. Scope excludes pending App/UI implementation and native qualification.

## Documented standards

No actionable documented-standard violations found. Authority consulted: AGENTS.md, docs/README.md, docs/agents/domain.md, docs/SPEC.md, docs/DESIGN-SYSTEM.md, docs/WHAT-GREW.md, and the TDD skill with tests/mocking guidance. No glossary or ADR was present.

The changes retain existing domain boundaries: the store selects compatible historical observations; the recorder verifies authorized filesystem identity without granting access or initiating scans; the presentation session retains useful comparison state across unsuccessful observations. No content-reading, cleanup authority or file-catalogue persistence was added.

New tests observe public store, recorder, scanner and session behavior using disposable filesystem data. They assert independent literal outcomes and identity preservation rather than collaborator call counts or private methods. The corruption fixture exercises a filesystem failure boundary; successful persistence is observed through public APIs. Removing the unrelated-scope case from coverage-change assertions accompanies an explicit public regression test for independent location baselines. Red/green provenance and seam authorization were not independently re-executed in this read-only review.

## Maintainability judgement

No actionable smell finding in this small increment. The existing fingerprint value type and recorder method keep the three identity checks together; extracting another identity abstraction is unnecessary for this change. Existing compressed formatting and string fingerprint schema predate this increment and do not establish a new documented-standard violation.

This is a source standards review, not a correctness certification, test run, App-flow review, or Light/Dark acceptance.

## Supplemental review — source `7c11a92`

Read-only review of `dce5c86...7c11a92 -- Packages/StillCore`, including the fixes at `60f0490`. No additional actionable Standards findings.

The incomplete-observation path now re-resolves the retained selected comparison even when its current endpoint survives. This prevents an expired older endpoint from leaving a stale numeric delta. The asynchronous lookup retains the existing active-token and cancellation guards before committing presentation state; a cancelled or superseded scan cannot commit its delayed lookup. No additional persistence authority or automatic scan is introduced.

Baseline-origin selection no longer uses unrelated expired global history as evidence that a newly observed location lost a baseline. The conservative first-baseline outcome avoids an unsupported cause claim without adding a per-location tombstone catalogue. Existing explicit Clear evidence remains separate.

The two added regressions exercise public archive/session behavior and independently specified outcomes. Tests were not rerun for this review; the parent reports 158 Swift Testing plus five XCTest cases passed. This supplement makes no App/UI or native qualification claim.
