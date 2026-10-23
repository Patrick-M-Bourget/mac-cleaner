# Explicit custom exclusions — M6

Custom exclusions are saved settings, created only by choosing a file/folder in the native picker, reviewing the resolved location and confirming **Save exclusion**. Unchecking an item or category changes only the current plan. It never creates a rule. This feature remains behind the future-milestones gate and is a secondary destination under Locations & access, not another sidebar item.

## Matching and authority

A rule stores an exact canonical absolute path, volume UUID and boundary kind: **this file path** or **this folder and its descendants**. It does not track inode/resource identity or search for renamed items. Renaming/moving a path out of a saved boundary stops matching; the saved rule remains at its original location. A replacement at the same path on the same volume remains excluded, even with a different resource identity. Another volume mounted at the same path does not match. Missing/disconnected rules remain saved and dormant; there is no path-only fallback when volume identity is unavailable. Parent folders overlap descendants explicitly; removing one rule leaves any other matching rule effective. Hardlink aliases outside the saved path remain independent paths.

The picker preview shows the resolved target and boundary. Symlinks/aliases resolved by the picker are represented by the displayed resolved target; the rule never follows later symlink descendants. Matching is component-based and case-sensitive against the saved canonical path spelling. Case-only renames therefore follow the same no-rename-tracking policy. No glob, process, extension, recommendation-only or automatic rule creation is supported in this slice.

Custom rules only reduce the explicitly selected filesystem inventory and its ordinary Downloads candidates. They cannot disable fixed safety protections, broaden scope or authorize cleanup. Independent external-tool inventories/guidance are not silently represented as covered by these filesystem rules; those adapters need their own validated policy integration before exposing cleanup.

## Coverage and refresh

Matched entries are skipped before file metadata supplementation or folder descent. Excluded contents/sizes stay unknown; a folder boundary counts as one skipped entry, not a count of unseen files. Accessible included coverage can complete, but the original whole-scope total remains unknown when entries are omitted. Growth can compare measured included aggregates only when exclusion fingerprints match. Selecting a scope entirely excluded by a rule yields an explicit unavailable/unknown result, not an empty folder or zero-size baseline.

The normalized rule set is fingerprinted with its semantics version. Every add/remove/reset changes scan policy, cancels old scan publication, invalidates approvals/findings and marks existing selections Refresh required. It does not silently delete or substitute selected identities. Old observations remain historical; adding from stale findings is blocked. Removing a rule never auto-selects newly visible files. A fresh explicit scan is required before new findings or affected choices become actionable. Global rule-set changes conservatively invalidate all selected-scope findings, even when a particular rule is dormant for a different volume.

## Persistence and management

At most 100 explicit rules are stored in a bounded, versioned local app-state file. Rule paths and volume identities are sensitive metadata, not file contents. Failed or corrupt rule loading blocks a new scan rather than silently dropping saved rules. Creation has a separate preview/Save step; cancellation stores nothing. Removal is explicit and tells the user to recheck. The fixed-protections explanation is read-only.

Clear completed history preserves custom rules. Guarded Reset removes custom rules only after the existing execution/unresolved-recovery maintenance guard succeeds. Reset also preserves diagnostics invalidation and existing growth/alert/login reset behavior. No rule-management operation deletes original files or revokes macOS access grants.
