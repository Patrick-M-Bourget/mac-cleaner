# Still — repository handoff

Approved product contract revision 0.9 · October 22, 2026. Prototype parity checkpoint · October 23, 2026.

Still is a working name. Native implementation is underway; see [development and validation instructions](DEVELOPMENT.md) for current capabilities and remaining gates. This bundle records the accepted product direction; it does not certify every native filesystem integration.

## Read in this order

1. [Implementation spec](SPEC.md): scope, architecture, safety boundaries and build sequence.
2. [Design handoff](DESIGN-HANDOFF.md): screens, interactions, components and acceptance criteria; [native design system](DESIGN-SYSTEM.md): mandatory shared components and UI change process.
3. [Milestones and full-feature preservation](MILESTONES.md), including deferred [M8 commercialization](COMMERCIALIZATION.md).
4. [Detailed technical specification](reference/macos-cleaner-technical-spec.md): execution, permissions, alerts and platform feasibility.
5. [UI state matrix](reference/macos-cleaner-ui-state-matrix.md) and [layout contract](reference/macos-cleaner-layout-contract.md): required exceptional states and geometry checks.

Supporting context: [PRD](reference/macos-cleaner-prd.md), [flow audit](reference/macos-cleaner-flow-audit.md), [design contract](reference/macos-cleaner-design-contract.md), [research](reference/macos-cleaner-research.md), [competitors](reference/macos-cleaner-competitors.md).

## Authority and change policy

**Current checkpoint:** [prototype-to-implementation parity audit](PROTOTYPE-PARITY.md), October 23. The audit is complete; the connected [flow lock](FLOW-LOCK.md) is user-confirmed under #45. Flow/presentation/delivery decisions Q1–Q30 are confirmed; [annotated visual proposal](CONNECTED-FLOW-DESIGN-REVIEW.md) is now user-approved; connected Downloads-first implementation may proceed. Review the parity ledger before further building; existing validation reports certify their stated boundaries, not the entire prototype experience.

SPEC.md and DESIGN-HANDOFF.md are the consolidated entry points. Detailed reference documents supply requirements where these are abbreviated. Revision 0.9 shared live-selection rules and milestone scope supersede earlier flows. Reference documents are historical detailed feature records; do not implement their conflicting draft, rescan or plan-persistence behavior. Historical research and prototype behavior are not requirements when they contradict these contracts. Resolve any remaining conflict explicitly before implementation rather than copying inconsistent behavior.

Update the relevant spec, design contract, state tests and visual reference together whenever behavior changes. Keep proposed features separate from accepted scope. Do not copy simulation labels, sample storage values or the prototype scenario picker into production.

Latest qualified slice: [What grew #52](WHAT-GREW.md), app `fb20196`, with [source/native/visual evidence](validation/what-grew.md). Completed baseline is consolidated in main through PR65; bounded #52 is merged through PR66. #54 is now locked under [RELEASE-ARCHIVES](RELEASE-ARCHIVES.md), with tight implementation underway. Full future milestones and M8 deferral remain preserved.

## Suggested repository layout

```text
Still/
  Still.xcodeproj
  App/                  # app lifecycle, composition, views, native bridges
  Packages/StillCore/   # domain, scan policies, planning, alerts, repository interfaces
  Packages/StillPlatform/ # filesystem, persistence and validated adapters
  Tests/Fixtures/       # synthetic/disposable data only
  UITests/
  docs/                 # copy this handoff bundle here
```

This is a starting structure, not a mandate to create a package for each type. Keep mutation capability behind a small, reviewable executor interface. UI previews and initial integration use fixtures.

## Initial repository checklist

- Create the Xcode macOS app, Swift packages and shared schemes; choose a stable bundle identifier/signing team.
- Pin the selected Xcode/Swift toolchain in developer documentation and CI. Provisional minimum deployment target is macOS 14; confirm before release.
- Build the fixed native window shell and fixture-backed flows before connecting mutation APIs.
- Add core unit tests and focused UI journey tests; run CI on macOS with no real user data or elevated privileges.
- Keep developer signing credentials outside Git. Separate development builds from notarized release configuration.
- Record platform feasibility findings in docs before enabling an adapter.

## Validation boundary

Native implementation and disposable-fixture validation are recorded in [DEVELOPMENT.md](DEVELOPMENT.md). Visual references and fixture interactions cannot certify native filesystem, persistence or permission behavior. [Visual review notes](visual/README.md) record exactly what has been exercised. Native implementation must pass SPEC.md and milestone-specific acceptance before capabilities ship.

## Approved decisions

See [decision record](DECISIONS.md) for the completed grilling rounds and [milestones](MILESTONES.md) for every retained feature. No feature is silently removed by narrowing M1.
