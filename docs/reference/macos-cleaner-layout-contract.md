> Historical revision 0.8 reference. Preserve feature detail, but implementation scope and interaction rules are superseded by [SPEC](../SPEC.md), [design handoff](../DESIGN-HANDOFF.md), and [milestones](../MILESTONES.md), revision 0.9. In particular, staged item drafts, clearing selections on rescan, persistent plans and installer-only selection are obsolete.

# Window and interaction stability contract — revision 0.8

October 22, 2026. Canonical preview: `storage-companion-direct.html`. This contract supplements the [state matrix](macos-cleaner-ui-state-matrix.md) and [technical specification](macos-cleaner-technical-spec.md).

## Cause and correction

The previous preview used content-driven height with a minimum-height layout. Longer settings screens, expanded details and short empty states therefore changed the surrounding window and conversation frame. The prototype review controls also wrapped according to their current text, and an appearing scrollbar could change content width.

The app now has a bounded viewport independent of screen content. Toolbar, sidebar and content occupy explicit layout tracks. Only the content pane scrolls during normal use; the sidebar scrolls independently if needed. A reserved scrollbar gutter prevents width shifts. Review controls have a reserved height. Expanded confirmation items scroll inside the sheet while its header and actions remain available. Geometry-changing design sliders have been removed from this handoff reference.

The preview adapts to its allocated viewport, up to a 760 px app height, without overflowing its enclosing page. At narrow preview widths the navigation reflows inside the same bounded window. This compact representation is review support, not a mobile application requirement.

## Production window behavior

- Initial native window target: 1120 × 760 points; minimum target: 900 × 640 points. These are design decisions to validate on supported Macs, including display scaling and localization.
- The user can resize the window. Remember user-selected bounds and sidebar width, and keep restored bounds within the available display area. Opening a different screen never resizes or recenters the window.
- Content, scan results, banners, validation messages, selection counts and disclosures must not drive window geometry. Avoid fitting the outer window to the current screen's ideal content size.
- Keep native titlebar/toolbar geometry and sidebar width stable. Prototype values are 63 px toolbar and 190 px sidebar; production should use platform metrics and a sensible bounded sidebar range rather than literal CSS pixels.
- Every pane must accept constrained size and allow its intended scroll container to shrink. No content-sized minimum height that expands the window to fit a long screen.
- Show one primary content scroll surface per destination. Avoid nested scrolling except an independent sidebar, a large file list where justified, or a bounded confirmation item list.
- Keep long paths and translated copy readable through wrapping or deliberate labelled truncation. Never truncate the only explanation of a destructive consequence or hide a primary action outside all reachable scroll areas.

## Navigation and interaction behavior

- New destinations start at the top on first visit. Preserve each destination's scroll offset when returning during the session. Re-rendering the same screen, changing selection, or receiving updated data must not reset its scroll offset.
- A deliberate prototype scenario change resets its sample scroll history. This is review behavior, not an automatic production reset policy.
- When a location/category changes within a file browser, reset the list position deliberately and update the inspector to a current item. Empty search results never retain a stale inspector.
- Opening a sheet preserves the underlying view and scroll offset. Keep keyboard focus inside the sheet, support Escape before execution, and restore focus to the originating control on dismissal. If that control no longer exists, choose a meaningful surviving control.
- Long sheet contents scroll in their item region. Confirmation and cancellation controls remain visible. Disclosure expansion does not grow the window or move it to another screen position.
- Use stable identities for rows and selections. Do not recreate the entire native screen on every checkbox change. Preserve focus, selection, inspector identity and scroll position during incremental updates.
- Preserve the last valid observation while refreshing, with an explicit stale/refreshing label. Do not flash zero, collapse the list, or replace the entire screen with a spinner for an incremental refresh.
- Coalesce asynchronous updates. A result from an older scan/request must not overwrite a newer scope or selection. Switching destinations must not restart work or silently create another scan.
- Disable only unavailable actions. State-specific copy and controls can change within the content region; the window frame and toolbar remain stable.
- Avoid animations of window size or full-screen layout during status changes. Respect reduced motion and reduced transparency. A spinner or small progress change must not alter neighboring control dimensions.

## Regression acceptance

At a fixed viewport/window size, capture the outer window, toolbar, sidebar and content bounds before and after each transition. Permit no content-driven outer size/position change; allow at most a 1-point rounding difference in automated assertions. Scroll changes are permitted only by user input, focus visibility, deliberate category navigation or documented restoration.

Exercise all six sidebar destinations; all 18 blocked/empty cases plus the ready case; the three growth comparison options; permission dialogs; long confirmation lists; disclosure expansion; selection count changes; scan progress/cancellation/completion; browser revalidation; partial results; and light/dark appearance. Repeat at initial and minimum native sizes, with long paths, larger text, translated strings, keyboard navigation and VoiceOver.

Revision 0.6 baseline DOM checks covered 19 cases at each of 320, 736 and 1024 px widths: **57 transitions, no content-driven size/position changes, no horizontal content overflow and no enclosing-page vertical overflow**. In the 688 px test viewport, app height remained 596 px at compact widths and 626 px at 1024 px, reserving 92/62 px for review controls. A separate 1248 px-wide pass also held geometry constant. All six sidebar destinations and three growth baseline choices preserved the frame. A selected-file confirmation, item expansion and cancellation preserved geometry and kept the sheet actions inside its bounds.

These are prototype checks. Native layout, real async updates, localization, accessibility focus and display restoration remain implementation acceptance gates. Use screenshots plus measured geometry in native UI regression tests; appearance alone is insufficient.

Final stress check: a four-action confirmation with every item disclosure expanded kept the 626 px app frame fixed; the 560 px sheet stayed inside it, its item region scrolled, both footer actions remained visible, and the enclosing page had no vertical overflow.

Revision 0.7 follow-up: direct Cleanup plan measured 626 px high at 1024 px width and 596 px high at 320 px width in the same 688 px viewport, with no horizontal content overflow. The broader state sweep above remains the revision 0.6 baseline, not a fresh full regression of revision 0.8.

## Review routes and selection — revision 0.8

Overview recommendations open the relevant item review. The item inspector offers Quick Look and Reveal in Finder; it has no “Exclude from cleanup” action. Item checkboxes determine this plan’s membership. Protected/offline items retain their read-only reason. Persistent scope exclusions belong in settings, not in the inspector.

Item review loads a scoped draft from the current plan. “Add selected items to cleanup plan” applies the reviewed scope and opens Cleanup plan; “Update cleanup plan” permits clearing an existing scoped selection. Preserve other categories and deduplicate target IDs. Leaving via Back does not apply an unsubmitted draft. Reopening review loads the committed plan. Browser-profile review follows the same contract. Inline category refinement edits the plan directly. Only “Review cleanup” opens the final confirmation; no review entry executes cleanup.

Keep a single context-labelled Back action, stable window bounds and destination scroll restoration. Selecting or inspecting an item must never navigate. Initial startup must not populate hidden selections.

## Native fixed-action hit testing

An interactive native `ActionStrip` is a fixed sibling below its `ScrollView` in a zero-spacing `VStack`. Keep content scrolling above it and preserve existing shell bounds. Do not put this strip in `ScrollView.safeAreaInset`: hosted macOS 26.6 evidence showed correctly drawn, enabled, in-bounds controls that failed accessibility hit-testing in that composition. The equivalent sibling layout passed the original Save action. Validate enabled/hittable buttons and the resulting action at initial/minimum bounds and both themes, rather than accepting visible geometry alone. [Diagnosis and qualification](../validation/footer-reachability.md).
