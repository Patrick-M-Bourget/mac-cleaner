# Prototype

Open [preview.html](preview.html) in a browser; GitHub's file view doesn't run HTML. It's a self-contained page with synthetic data. It touches no real files, permissions or notifications.

The Scope selector outside the app switches between **M1 · Personal build** and **Future milestones · Full design**. **Full design is the UI reference.** The M1 mode reflects the old Downloads-only scope and is superseded (RESET Decision 5). Scenario controls and simulation labels are review tooling, not production UI.

- [Personal build, light](personal-light.png)
- [Personal build, dark](personal-dark.png)
- [Full design, dark](roadmap-dark.png)
- [Editable fragment](preview-source.html)

The example data uses an internal `installers` key for the Downloads action. Don't copy fixture identifiers into the native model.

## Native navigation experiment (#537)

In a Debug build, open **Debug → Design gallery → Navigation prototype**. Compare **A · Current**, **B · Inset glass**, and **C · System sidebar** with the floating layout picker (or ⌘[ / ⌘]). Light/Dark, Opaque chrome, and bright/dark/colorful synthetic backdrops are local review controls. Navigation changes only synthetic examples; no scan, cleanup, or permission action runs from the prototype.

The gallery renders the native prototype itself, including its shared sidebar and content examples. There is no separately maintained gallery approximation. The existing HTML remains the production visual reference until a rendered native direction is approved. If retained, promote the approved shared components into the workspace, keep the gallery using those components, and update the HTML reference and design decisions together. The prototype alone does not complete #537.
