# Prototype

Open [preview.html](preview.html) in a browser; GitHub's file view doesn't run HTML. It's a self-contained page with synthetic data. It touches no real files, permissions or notifications.

The Scope selector outside the app switches between **M1 · Personal build** and **Future milestones · Full design**. **Full design is the UI reference.** The M1 mode reflects the old Downloads-only scope and is superseded (RESET Decision 5). Scenario controls and simulation labels are review tooling, not production UI.

- [Personal build, light](personal-light.png)
- [Personal build, dark](personal-dark.png)
- [Full design, dark](roadmap-dark.png)
- [Editable fragment](preview-source.html)

**Locations** retains scanned folders, Protected items and Saved data; **System access** immediately follows it and displays optional Full Disk Access guidance directly (#527). The HTML uses synthetic access status and never opens System Settings.

The example data uses an internal `installers` key for the Downloads action. Don't copy fixture identifiers into the native model.
