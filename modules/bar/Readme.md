# Bar

One top bar per monitor (except the excluded portrait panel). Three isles:

- **left** — where am I: workspaces, submap indicator, group chip, layout glyph.
  The workspace pill's order and icons (LEO-343) come from the hyprfocus
  declaration, never a hardcoded list: each monitor shows the active mode's
  admitted scenes for that monitor's role (`base.scenes[name].icon`, declared
  order from `modes.<id>.scenes`), plus any other real workspace that still
  holds windows, appended after. See
  [`WorkspaceSwitch.js`](WorkspaceSwitch.js) for the pure logic (`barWorkspaces`,
  `roleForScreen`) and its header for how a monitor's primary/secondary role is
  read off the `geometry` store, absent any store that publishes the role
  mapping directly.
- **Dofus** — appears only on the `gaming` workspace while Dofus clients are
  present. Mirrors the Hyprland group order from `DofusWindows`, highlights the
  focused member, focuses on click, and exposes the swap-detector controls from
  `DofusSwap` (calibrate, learn per character, run/stop). It is a bar isle, not
  attached to any window or Hyprland group.
- **centre** — what's playing / what to adjust: media, brightness, volume.
- **right** — when is it / what's the mood: clock, mode pill, calendar entry.

Autohide follows the active mode from `Focus`: `deep` sheds most isles;
`game` hides the full bar without shedding. A SUPER-tap IPC reveal and a thin
hot strip at the top edge both wake it.

The Dofus isle uses `DofusWindows.windows` as its membership source and
`DofusSwap` for detector state; it does not rebuild group membership or swap
state.

Bar-triggered panels (projects, calendar, mood, notifications) open on the bar
instance that triggered them. IPC/keybind-triggered panels resolve the active
monitor through [`services/PanelBus.qml`](../services/PanelBus.md).

See [`services/DofusWindows.qml`](../services/DofusWindows.qml) and
[`services/DofusSwap.qml`](../services/DofusSwap.qml) for the data contracts.
