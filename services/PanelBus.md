# PanelBus

Shared state and monitor routing for bar-triggered and IPC-triggered panels.

## State

- `open` — which bar panel is currently open (`"projects"`, `"calendar"`,
  `"mood"`, or `""`).
- `anchorScreen` / `anchorX` — the screen and horizontal anchor the bar pill
  that opened the panel was on. When the caller also passes an `isleId`,
  `anchorX` resolves from the isle's published dock document in the `geometry`
  store so the panel tracks the isle's live position; otherwise it falls back
  to the click coordinate.
- `anchorIsleId` — the isle that opened the current panel (`""` for IPC/keybind
  opens), used for dock-aware panel positioning.
- `sceneByScreen` — per-screen active workspace/scene name, fed by raw
  compositor events (`workspace`, `workspacev2`, `focusedmon`, `focusedmonv2`)
  and shared with gap-aware surfaces such as Toasts. `workspacev2` carries
  `WORKSPACEID,WORKSPACENAME`; `focusedmonv2` carries `MONNAME,WORKSPACEID`,
  which is resolved to a name through `Hyprland.workspaces` before the map is
  updated. The map is also seeded once at startup from `hyprctl monitors`,
  because a shell that just started has missed every event and would render
  nothing until the first workspace change. The seed never overwrites an
  entry, so an event that lands while the snapshot is in flight wins.
- `activeScreen` — the seat: the keyboard's monitor, read from hypr's
  `seat.lua` publish to the `geometry` store's `seat.monitor` key (one seat,
  cross-repo — the keyboard's monitor is the only answer to "where is the
  user"). Falls back to `Hyprland.focusedMonitor` only before the first
  publish (shell just started, or an old store with no `seat` key yet).
  `focusedMonitor` itself tracks the POINTER on this desk
  (`mouse_move_focuses_monitor = true`), never used past that fallback: a
  widget opening "where the user is" must not follow the mouse to a different
  monitor than the keyboard is on.

## Monitor routing contract

| Invocation       | Target monitor                                     |
| ---------------- | -------------------------------------------------- |
| Bar click (pill) | The bar instance that was clicked (`anchorScreen`) |
| IPC / keybind    | The currently focused monitor (`activeScreen`)     |
| Missing anchor   | Falls back to `activeScreen`                       |

Panels bind their `PanelWindow.screen` to `PanelBus.screenObject(...)` rather
than resolving `Quickshell.screens` inline. `screenObject(name)` returns the
named screen, or the active screen when the name is empty.

Use `PanelBus.toggle(name, screen, x, isleId)` from bar pills and
`PanelBus.openFromIpc(name)` from IPC handlers so the anchor is set before the
panel becomes visible. The `isleId` is the stable bar-isle identifier from
`modules/bar/Readme.md`; omitting it makes the panel fall back to the click
coordinate.

## Covered panels

- `modules/bar/ProjectsDashboard.qml`
- `modules/bar/CalendarPanel.qml`
- `modules/bar/MoodPanel.qml`
- `modules/bar/NotificationCenter.qml`
- `modules/bar/SysPanel.qml` (via `SysMon`, which routes IPC to `PanelBus.activeScreen`)
- `modules/bar/Toasts.qml`
- `modules/control/SystemCenter.qml`
- `modules/control/ControlPanel.qml`
- `modules/dofus/TeamSelector.qml`
- `modules/dofus/ClassAssigner.qml`
- `modules/obsidian/ObsidianCreate.qml`
- `modules/cheatsheet/CheatSheet.qml`
- `modules/whichkey/WhichKey.qml`
- `modules/bar/WorkspaceSwitcher.qml`
- `modules/common/WindowRename.qml`
