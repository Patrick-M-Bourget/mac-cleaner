# Visual reference — revision 0.9

Open [preview.html](preview.html) locally in a browser. GitHub's file view does not run HTML. The preview is a self-contained exported page with synthetic data; no access to actual files, permissions, notifications or cleanup APIs occurs.

The Scope selector outside the app switches between **M1 · Personal build** and **Future milestones · Full design**. The first mode offers Downloads cleanup and hides future primary destinations/actions. The second preserves the broader design. Scenario controls and simulation labels are review tooling, not production UI. Some secondary management screens retain future controls as design coverage; MILESTONES.md determines when they ship.

- [Personal build — light](personal-light.png)
- [Personal build — dark](personal-dark.png)
- [Full roadmap — dark](roadmap-dark.png)
- [Editable fragment](preview-source.html)

Selections update a single live plan; Back preserves them. Preview reload starts a new unexecuted session (native explicit Quit has that role). Appearance may persist in the wrapper. Switching to Personal mode removes non-M1 selections deliberately as a review-only scope change.

## Checks performed

- Selected one PDF in item review; Back → Cleanup plan retained exactly that target and showed mixed Downloads selection.
- Downloads bulk selection → confirmation showed six exact files / 4.1 GB, including a PDF and nested video path.
- Cancelled refresh disabled execution and retained pending identities; successful refresh retained all six eligible choices without adding targets.
- Reload started an empty selection; both light/dark appearances rendered; roadmap navigation and categories remained accessible.
- Roadmap outer frame measured 626 px high, top 62 px in the test viewport, with no horizontal content overflow.

These are representative browser checks, not a complete automated state sweep or native certification. Changed-target removal, crash reconciliation, real filesystem identities, Reset blocking and OS integrations require native tests. The scenario picker intentionally replaces fixtures, unlike normal navigation. Native implementation must follow SPEC.md where simulated/historical secondary screens are incomplete.

## Production interpretation

The example data uses an internal `installers` fixture key for the broader Downloads action; production domain naming should use Downloads/trash-file. Do not copy those fixture identifiers into the native domain model. Individual Trash operations do not promise original directory hierarchy or automatic restoration.

The M1 summary prioritizes “Selected for Trash” and explicitly says space stays occupied until Finder empties Trash. Future actions retain separate potentially released and Trash-held estimates. Native material, SF Symbols, accessibility and system text styles replace the web rendering.

## Native implementation evidence

The reference PNGs above remain the approved design comparison, with the later explicitly white Light sidebar clarification. Current native [fidelity captures](fidelity/) and their [main manifest](fidelity/manifest.json) / [exclusions manifest](fidelity/exclusions/manifest.json) record source `524f878`, actual rendered dimensions, test identifiers and hashes. See [fidelity validation](../validation/visual-fidelity.md) for observed differences, the native recheck exception and exact public regression results. Earlier `native-design-system` captures preserve the first implementation checkpoint rather than replacing the approved reference or representing every subsequent source revision.

The subsequent [Downloads scope guidance captures](downloads-scope-guidance/manifest.json) preserve sixteen original native images at application `7d12f12`, in Light/Dark and hosted initial/minimum sizes. [Scope validation](../validation/downloads-scope-guidance.md) records the checks and disabled-review correction; [checkbox evidence](../validation/checkbox-content-anchor.md) preserves the separate baseline/fix captures. These supplement the historical `524f878` fidelity captures without relabelling their provenance.


Read-only tool follow-up: [Docker captures](docker-inventory/manifest.json) at `fa17dd4` and [pip captures](pip-inventory/manifest.json) at `174c96a` record eight original images each, both appearances and initial/minimum dimensions. All sixteen were individually viewed. Docker UI uses a synthetic report; pip UI runs the real verified bundled runtime against an owned synthetic cache. These supplement the historical design references; qualification details and exact run outcomes are in the corresponding adapter validation reports.
