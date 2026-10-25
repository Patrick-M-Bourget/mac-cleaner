# Release-archive guidance — locked #54 contract

User confirmed Q1–Q7 and consolidated contract October25,2026; documentation lock and implementation authorized. Parent #45, parity M01–M02. This lock is not qualification evidence.

1. **Guidance only:** add Release archives within the existing M6-gated App-managed storage screen. No selection, cleanup action, archive/dSYM deletion, background scan or Automation/Accessibility permission. Do not enable #17 or M8.
2. **Unknown amount:** display Not inspected, never zero, reclaimable bytes or a cleanup estimate. No discovery, measurement, picker or recursive archive/library traversal. Release archives cannot use the existing arbitrary selected-object measurement route.
3. **Existing architecture:** one category in the current list/detail layout, labelled Protected from Still cleanup. No sidebar or Cleanup plan category. Other categories keep their existing behavior.
4. **Retention:** explain that archives and matching debug symbols for distributed builds should be retained because they may be needed to diagnose crashes. No age-based deletion advice or obsolete/safely replaceable judgement.
5. **Explicit actions:** Open Xcode and Read Apple guidance, with Window → Organizer → Archives instructions. Opening launches Xcode only; do not claim direct Organizer navigation. Use existing native application lookup/launcher and explicit browser link, no guessed deep link or scripting.
6. **Unavailable/failure:** retain the selected category and instructions, explain Xcode could not be opened, permit explicit retry or Apple guide. No installer, auto-retry, permission prompt or filesystem fallback.
7. **Order/default/context:** Release archives first, matching prototype. Device backups stays initial selection; existing session category choice and Back to Overview behavior remain. No navigation persistence/framework or other category redesign.

## Implementation and verification boundary

Reuse shared page/badge/summary/status presentation. Give this category a shared pure guidance component and inert Gallery example where needed. Focused existing public inventory/guidance/launcher and UI journey boundaries verify protected/uninspected behavior, native route/context/actions and honest failure at controlled system boundaries. Review Light/Dark at initial/minimum. Preserve existing managed categories and cleanup choices. Do not repeat unrelated suites or add a separate test per copy string. Genuine OS app lookup/opening retains documented integration limits; a fixture is not proof of every Xcode installation.

Update SPEC, DESIGN-HANDOFF, DESIGN-SYSTEM and PROTOTYPE-PARITY together. M01–M02 remain pending until source/public journey/visual qualification. Do not use #54 to close broader #31 owner-app/platform acceptance without its own evidence.

## Official guidance

- Organizer: https://help.apple.com/xcode/mac/current/en.lproj/dev1bc569500.html
- Retaining distributed-build archives/debug symbols: https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information

Verified primary sources during grilling; do not substitute sample prototype amounts or claim unsupported direct-pane navigation.
