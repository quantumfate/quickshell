//@ pragma UseQApplication
// Root shell config. Loaded by: qs -c quantumfate  (or -p /path/to/shell.qml)
// Each top-level widget is a Scope/window. Add bars, notifications, etc. here.
import Quickshell
import "modules/common"
import "modules/cheatsheet"
import "modules/bar"

ShellRoot {
    // `qs -c quantumfate ipc call help all` — annotated IPC overview.
    IpcHelp {}

    // Top bar (per-monitor), replacing waybar. Hosts the Dofus taskbar.
    Bar {}

    // Notification toasts + persisted history panel (Notify is now the system
    // notification daemon). Toasts show on the wide screen; the center is docked
    // wherever it's toggled.
    Toasts { screen: Quickshell.screens.find(s => s.name === "DP-1") ?? null }
    NotificationCenter {}

    // System-monitor detail popout (CPU/RAM/disk/net), driven by the SysMon bus.
    SysPanel {}

    // Window renaming: headless `window rename`, and the `window prompt` widget
    // opened from the Dofus team submap.
    WindowRename {}

    // Themed which-key keybind cheatsheet. Toggled via IPC.
    CheatSheet {}

    // Passive peek variant: non-focus, non-dimming contextual panel driven by
    // the Hyprland submap event system (hypr/events/peek.lua).
    CheatSheetPeek {}
}
