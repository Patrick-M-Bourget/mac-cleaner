# Still — repository handoff

Revision 0.8 · October 22, 2026 · Ready for repository setup and native-shell development.

Still is a working name. No native implementation exists yet. This bundle records the accepted product direction; it does not certify native filesystem integrations.

## Read in this order

1. [Implementation spec](SPEC.md): scope, architecture, safety boundaries and build sequence.
2. [Design handoff](DESIGN-HANDOFF.md): screens, interactions, components and acceptance criteria.
3. [Detailed technical specification](reference/macos-cleaner-technical-spec.md): execution, permissions, alerts and platform feasibility.
4. [UI state matrix](reference/macos-cleaner-ui-state-matrix.md) and [layout contract](reference/macos-cleaner-layout-contract.md): required exceptional states and geometry checks.

Supporting context: [PRD](reference/macos-cleaner-prd.md), [flow audit](reference/macos-cleaner-flow-audit.md), [design contract](reference/macos-cleaner-design-contract.md), [research](reference/macos-cleaner-research.md), [competitors](reference/macos-cleaner-competitors.md).

## Authority and change policy

SPEC.md and DESIGN-HANDOFF.md are the consolidated entry points. Detailed reference documents supply requirements where these are abbreviated. The revision 0.8 review/selection rules supersede earlier flows. Historical research and prototype behavior are not requirements when they contradict these contracts. Resolve any remaining conflict explicitly before implementation rather than copying inconsistent behavior.

Update the relevant spec, design contract, state tests and visual reference together whenever behavior changes. Keep proposed features separate from accepted scope. Do not copy simulation labels, sample storage values or the prototype scenario picker into production.

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

The prototype exercised representative selection, confirmation, recovery and layout paths. It was not exhaustively regression-tested after every revision. In particular, the latest restoration-order fix still needs a dedicated regression test. Production must independently validate all state-matrix branches, keyboard/VoiceOver behavior, localization, persistence and real permissions. Repository setup can proceed now; release support claims remain gated.
