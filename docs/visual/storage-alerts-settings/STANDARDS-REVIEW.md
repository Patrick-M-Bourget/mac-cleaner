# #27 Standards review

Reviewed production freeze `336fcb9` against `65a836c`; read AGENTS.md, docs/README.md, MILESTONES.md, DESIGN-SYSTEM.md, STORAGE-ALERTS.md and docs/agents. No glossary/ADR or additional code standards were present. Read-only source review; no tests or native captures executed here.

## Documented standards

No blocking violations found. The settings compose existing PageHeader, VolumeSummary, SettingsRow, MonitoringDetails and StatusRow with semantic tokens. New threshold/permission/quiet explanation primitives are pure presentation reused by the live view and collapsed inert Gallery, consistent with DESIGN-SYSTEM component reuse. Capacity display refresh remains a direct CapacityRefreshController action. Policy, persistence and stale authorization rejection remain behind AlertMonitoringController; applying a draft rolls back policy on save failure before publishing applied bytes. No new filesystem authority or architecture was introduced.

**P3 — Gallery coverage completeness:** `Still/App/DesignGallery.swift:53–56` shows valid-pending, unknown-capacity, unknown permission and denied permission, but no known-capacity invalid-draft state: the second editor supplies `hasCurrentTotal:false` and defaults `invalidDraft:false`. Its new inline validation StatusRow (`StorageAlerts.swift:143–145`) cannot appear in Gallery. DESIGN-SYSTEM step2 asks for meaningful states and step4 for changed-state visual accounting. Add or account for this specific state during qualification; this is a small presentation-evidence omission, not a production behavior blocker.

## Heuristic judgement

No actionable Fowler smell requiring refactoring in this bounded diff. Existing controller responsibility remains coherent: it owns the monitoring policy and authorization lifecycle while the view owns local UI disclosure/launch feedback. A few duplicated byte literals in synthetic fixtures do not justify a new configuration/domain abstraction. The new authorization generation is specific stale-response protection rather than a speculative generic concurrency framework.

Native layout/accessibility and real notification delivery are outside this source review; qualification must retain their explicit limits.
