# PanelBus

Shared state and monitor routing for bar-triggered and IPC-triggered panels.

## State

- `open` — which bar panel is currently open (`"projects"`, `"calendar"`,
  `"mood"`, or `""`).
- `anchorScreen` / `anchorX` — the screen and horizontal anchor the bar pill
  that opened the panel was on.
- `activeScreen` — the currently focused Hyprland monitor, polled once per
  second.

## Monitor routing contract

| Invocation       | Target monitor                                     |
| ---------------- | -------------------------------------------------- |
| Bar click (pill) | The bar instance that was clicked (`anchorScreen`) |
| IPC / keybind    | The currently focused monitor (`activeScreen`)     |
| Missing anchor   | Falls back to `activeScreen`                       |

Panels bind their `PanelWindow.screen` to `PanelBus.screenObject(...)` rather
than resolving `Quickshell.screens` inline. `screenObject(name)` returns the
named screen, or the active screen when the name is empty.

Use `PanelBus.toggle(name, screen, x)` from bar pills and
`PanelBus.openFromIpc(name)` from IPC handlers so the anchor is set before the
panel becomes visible.

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
