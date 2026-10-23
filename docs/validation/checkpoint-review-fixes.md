# Checkpoint standards/spec corrections

Review base e5bf9d6; fixes initially committed e1cd7ab and merged clean hosted-evidence tip 5cac309. No new product scope or route model is introduced.

## Shared rhythm

Repeated screen spacing/insets now use the existing StillDesign.Space roles. Metadata uses xs; rows/insets sm; grouped labels/target lists md; compact confirmation sections lg; ordinary sections xl. The old 5/10/18/20-point values normalize to 4/12/16/24 through those roles. Structural zero spacing and native control/window/bounded-sheet geometry remain deliberate local exceptions, documented in DESIGN-SYSTEM. Sidebar/category meaning, fixed geometry, actions, state and navigation contracts are unchanged. Existing route booleans were reviewed without establishing an exclusivity bug; no optional enum refactor overlaps #30.

This is token reuse, not a new visual direction. Existing hosted captures remain evidence only for their stated 38a593e source. No new cosmetic UI-test loop or newly qualified screenshot is claimed for the small rhythm normalization; shared appearance/manual qualification boundaries remain explicit.

## Alerts off during an awaited service operation

The controller invalidates delivery and monitoring generations when opting out, stops monitoring and removes pending threshold requests before attempting to persist the off preference. A persistence failure therefore cannot leave the old submission current. Late accepted submissions follow stale-success pending-request cleanup; late failures do not alter policy, persistence or Off status. A disabled/superseded opt-in also stops after awaited authorization/settings results without changing the new state or starting a stale permission request.

The existing public delivery boundary receives the opt-in transition; it does not replace threshold/authorization eligibility policy. A controlled pending service success/failure test first failed against the old non-invalidating behavior (late request/status/persistence changed), then passed after invalidation. This uses a controlled completion and sink, not OS notification delivery or permission prompts. Removing pending requests cannot retroactively undo a notification already presented by the OS.

## Bounded verification

111 StillCore tests and 18 alert/lifecycle tests passed. Native Debug build-for-testing and Release compilation passed (Release signing disabled; no distribution claim). A grep of production app sources found no remaining nonzero spacing/padding rhythm literals; structural zero spacing and geometry are intentionally retained. No native UI journey, OS grant, user-data scan or personal cleanup was run for these corrections. Clean hosted History/scanner evidence integrated from 5cac309 is preserved with its pinned source and qualification limits.
