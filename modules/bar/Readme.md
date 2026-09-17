# Bar

One top bar per monitor (except the excluded portrait panel). Three isles:

- **left** — where am I: workspaces, submap indicator, group chip, layout glyph.
  The workspace pill's order and icons (LEO-343) come from the hyprfocus
  declaration, never a hardcoded list: each monitor shows the active mode's
  admitted scenes for that monitor's role (`base.scenes[name].icon`, declared
  order from `modes.<id>.scenes`), plus any other real workspace that still
  holds windows, appended after. The focused row (LEO-371) gets an accent
  pill (`Theme.accent`, so it reads as the active mode's colour) and the
  scene's name is shown next to the row, elided laptop-safe. See
  [`WorkspaceSwitch.js`](WorkspaceSwitch.js) for the pure logic (`barWorkspaces`,
  `roleForScreen`, `activeName`) and its header for how a monitor's
  primary/secondary role is read off the `geometry` store, absent any store
  that publishes the role mapping directly.
- **Dofus** — appears only on the `gaming` workspace while Dofus clients are
  present. Mirrors the Hyprland group order from `DofusWindows`, highlights the
  focused member, focuses on click, and exposes the swap-detector controls from
  `DofusSwap` (calibrate, learn per character, run/stop). It is a bar isle, not
  attached to any window or Hyprland group.
- **centre** — what's playing / what to adjust: media, brightness, volume.
- **right** — when is it / what's the mood: clock, mode pill, calendar entry.
  The mode pill (`ModePill.qml`) shows the active mode's declared name
  (`hyprfocus.json`'s `modes.<id>.name`; "Neutral" at rest) tinted by
  `Theme.accent`, which already tracks the mode's declared
  `presentation.accent_role`.

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
