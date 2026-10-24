# Shell and appearance qualification — #53

Contract [SHELL-APPEARANCE](../SHELL-APPEARANCE.md) locked October 24,2026 at f5174a6. Public appearance-service boundary explicitly approved by user; existing public UI journeys remain approved. Implementation started in isolated issue53 worktree. No new test result, source acceptance or native capture is claimed yet. Record actual red→green cycles and source-bound original theme/size captures here before integration.

## First public shell tracer

Test-only source `a66d39e` adds an owned two-file Downloads journey through existing public UI. After scanning and category selection it expects one accessible category badge, accurate Plan/History context, preserved choices across navigation/themes, stable outer bounds, hidden badge after deselection and unchanged original bytes. Local Xcode27.1 build-for-testing passes. Hosted native run40090379307 at a66d39e fails as intended on the missing accessible category badge (line38,30.798s), after successfully selecting both owned files. The original900×640 Light capture and export manifest are preserved at ../visual/shell-appearance/40090379307-red/. Individual review also confirms the editable Plan is incorrectly labelled Read-only metadata; no test-fixture correction is needed. This is failing baseline evidence, not acceptance.

The appearance implementer uses the explicitly approved public preference-service seam. Typed monitoring presentation is being developed through the existing approved public alert-controller/controlled OS-clock seam; underlying polling, authorization and delivery policy must remain unchanged. No product monitoring capability is promoted.

Public appearance service checkpoint agentd346851/root92521d8 adds four actual red→green journeys: missing/default and persisted recreation; invalid/unreadable no-repair fallback; failed write retaining session choice and explicit retry; independent remove-success Reset behavior. Focused4/4 pass; logs /tmp/shell53-cycle1-red.log through cycle4-green.log retained in implementation cache. App composition/native appearance qualification remains pending.

## Native badge/context vertical and appearance red

`40090744516` at `efb059a` passes the selected-category/destination journey45.892s. Both original900×640 Light/Dark captures individually reviewed: one badge for two selected Downloads files, correct Plan context, stable geometry and reachable actions. Test also checks History context, choice preservation, badge hidden after deselection and unchanged fixture bytes. This bounded pass does not qualify appearance persistence or monitoring presentation. Originals/manifests: `docs/visual/shell-appearance/40090744516`.

Appearance-only tracer `40090809557` at `5ae8d7d` fails as intended atline81 after Dark→Quit→relaunch restores Automatic instead (11.194s). The owned-state fixture reaches the intended failure; no test correction required. Original900×640 Light/Automatic reviewed and preserved in `docs/visual/shell-appearance/40090809557`. App wiring follows this observed red; public policy4/4 alone was not sufficient.

Restricted source reviews of services atf82abf8 found Reset load/remove exceptions could leave shell readiness stale, and present-but-invalid capacity could say on despite rejected metadata. Source correctiona21f1a0 marks typed attention while preserving policy/lifecycle behavior. Follow-up detail wording and app composition qualification remain pending. StorageAlerts43/43 pass after ten public red→green policy journeys (33existing+10new), recorded by the owner; not native OS certification.
