# Bar

One top bar per monitor (except the excluded portrait panel). Three isles:

- **left** — where am I: workspaces, submap indicator, group chip, layout glyph.
  The workspace pill's order and icons (LEO-343) come from the hyprfocus
  declaration, never a hardcoded list: each monitor shows EVERY scene the
  active mode admits for that monitor's role (`base.scenes[name].icon`,
  declared order from `modes.<id>.scenes`), plus any other real workspace
  that still holds windows, appended after. Entering a mode launches
  nothing (LEO-373): an admitted scene with no windows shows **dormant**
  (dimmed, `Theme.c.overlay0` + reduced opacity — synthesized even when
  Hyprland has not created its workspace yet, so the row is there from mode
  entry, not just after a window appears), one with at least one window
  shows **playing** (`Theme.c.lavender`), and the one active on this
  monitor is **focused** (LEO-371's accent pill, `Theme.accent`) regardless
  of whether it is also playing. Dormant is a display state only — the
  workspace is still admitted and its row still dispatches `name:<scene>`
  on click, focusing or creating it. The scene's name is shown next to the
  focused row, elided laptop-safe. See
  [`WorkspaceSwitch.js`](WorkspaceSwitch.js) for the pure logic
  (`barWorkspaces`, `rowState`, `roleForScreen`, `activeName`) and its
  header for how a monitor's primary/secondary role is read off the
  `geometry` store's `roles` map (LEO-368) — hypr's `conf/host.lua`
  publishes it explicitly next to the per-output gaps, so `roleForScreen`
  reads a real fact instead of guessing from the gaps map's key order. An
  unconnected or ignored output is simply absent from the map, never
  defaulted onto a role.
- **Dofus** — appears only on the `gaming` workspace while Dofus clients are
  present. Mirrors the Hyprland group order from `DofusWindows`, highlights the
  focused member, focuses on click, and exposes the swap-detector controls from
  `DofusSwap` (calibrate, learn per character, run/stop). It is a bar isle, not
  attached to any window or Hyprland group.
- **centre** — what's playing / what to adjust: media, brightness, volume.
- **right** — when is it / what's the mood: clock, mode pill, calendar entry.
  The mode pill (`ModePill.qml`) shows the active mode's declared name
  (`hyprfocus.json`'s `modes.<id>.name`; "Work" at rest — `work` is the
  default/resting mode) tinted by `Theme.accent`, which already
  tracks the mode's declared `presentation.accent_role`. Clicking it opens
  `MoodPanel.qml`, whose mode picker offers only the declaration's
  non-`hidden` modes (`Hyprfocus.ids()`) — `neutral` stays reachable solely
  as the hypr modes submap's recovery mode, never as a picker choice and
  never a fallback a lapsed timed mode settles to (see `previous` in
  `schemas/focus.schema.json`), so the resting pill can say "Work" honestly
  without inviting anyone back to `neutral`. Its palette lease field uses
  `modules/common/PalettePicker.qml` (a wrapping swatch grid, readable at any
  palette count) paired with `modules/common/HoverDetail.qml` (a fixed-height
  slot for hover-preview text, so pointing at a chip never resizes the
  panel) — both components are shell-wide, not mood-panel-specific, for the
  theme panel to reuse.

Autohide follows `Hyprfocus.current.presentation.bar_autohide` — the
declaration's own per-mode flag, not the retired `deep`/`game` mode ids. A
SUPER-tap IPC reveal and a thin hot strip at the top edge both wake it.

The Dofus isle uses `DofusWindows.windows` as its membership source and
`DofusSwap` for detector state; it does not rebuild group membership or swap
state.

Bar-triggered panels (projects, calendar, mood, notifications) open on the bar
instance that triggered them. IPC/keybind-triggered panels resolve the active
monitor through [`services/PanelBus.qml`](../services/PanelBus.md).

See [`services/DofusWindows.qml`](../services/DofusWindows.qml) and
[`services/DofusSwap.qml`](../services/DofusSwap.qml) for the data contracts.
