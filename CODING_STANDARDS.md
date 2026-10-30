# Coding standards

For reviewers: apply every rule to the diff. Each points at its Decision in `docs/RESET.md`, which wins where they differ. `scripts/check.sh` already checks test seams, Decision numbering, GLOSSARY's off-screen terms and pinned stored keys, so leave those to it.

## Behaviour

- **Say why.** A refusal, an unreadable place or an unknown size reads as what it is ("Needs access", "—", the refusal's reason), never as empty, zero or absent (Decision 62).
- **Override only what was shown.** When ticking overrides a guard, it overrides only the guard the user saw on that row. Every other check still runs at Clean up (Decision 78).
- **Recheck at the click.** Clean up checks every item again just before acting. Nothing is forced, and production asks an app to quit only through `NSRunningApplication.terminate()` (Decisions 78, 79).
- **One selection.** Ticks live in CacheDropCore `CleanupSelections`, shared by Smart clean, the plan and Applications. Recommended items start ticked; held items never do (Decisions 67, 78).
- **Waiting state.** Skeleton rows only while a page's content isn't known yet. A rescan keeps the rows on screen, dimmed with `.waitingForScan` (Decisions 61, 80).

## UI

- **Design system.** Spacing, type, colours and radii come from `CacheDropDesign` tokens; reuse the components in `DesignSystem.swift`. A new or changed shared component also appears in `DesignGallery.swift`.
- **Button rule.** In-row actions are links; bordered capsule buttons go in the bottom bar and sheet footers; close and stop use `CloseButton` (Decisions 65, 73).
- **Plain words.** User-side names and US spelling (Decision 66). A ticket's approved wording ships unchanged.
- **Identifiers.** Existing accessibility identifiers stay. New interactive elements get one, exposed as `docs/agents/ui-testing.md` describes.

## Structure

- **One rule, one place.** Logic that decides what is offered, ticked, held or refused lives once in CacheDropCore and is tested there. Views read it rather than re-derive it.
- **Decisions and SPEC follow the code.** A behaviour change gets a Decision. An older Decision it changes gets an "amended by Decision N" pointer in place, and `docs/SPEC.md` is updated where it states the old behaviour.
- **Tests.** Core logic is tested in CacheDropCore with temp fixtures only. The UI journey of each touched page is updated.
