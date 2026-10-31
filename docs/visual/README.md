# Prototype

Open [preview.html](preview.html) in a browser; GitHub's file view doesn't run HTML. It's a self-contained page with synthetic data. It touches no real files, permissions or notifications.

The Scope selector outside the app switches between **M1 · Personal build** and **Future milestones · Full design**. **Full design is the UI reference.** The M1 mode reflects the old Downloads-only scope and is superseded (RESET Decision 5). Scenario controls and simulation labels are review tooling, not production UI.

- [Personal build, light](personal-light.png)
- [Personal build, dark](personal-dark.png)
- [Full design, dark](roadmap-dark.png)
- [Editable fragment](preview-source.html)

The example data uses an internal `installers` key for the Downloads action. Don't copy fixture identifiers into the native model.

## Native workspace experiment (#537)

In a Debug build, open **Debug → Design gallery → Full window prototype**. The prototype shows the complete **Cleanup plan** and **Overview** windows; **Review cleanup** opens a native **Review sheet**. The gallery renders these same components directly. Amounts and counts come from one synthetic selection. All cleanup, scan, and access actions are inert. Only the two requested destinations navigate within the prototype; other sidebar examples remain in place.

The neutral window background, aligned glass sidebar and reading pane, shared summary/row styles, and action regions form one light-mode treatment. Light/Dark and Opaque chrome are local review controls. Semantic surfaces adapt to Dark now; dark-mode visual tuning follows approval of the light composition. The old sidebar-only variants are preserved in the branch history.

The existing HTML remains the production visual reference until a rendered native direction is approved. If retained, promote the approved shared components into the workspace, keep the gallery using those components, and update the HTML reference and design decisions together. Prototype screenshots and validation records stay outside the checkout. The prototype alone does not complete #537.
