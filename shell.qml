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

    // In-shell feedback toasts (Notify bus), on the multibox screen.
    Toasts { screen: Quickshell.screens.find(s => s.name === "DP-1") ?? null }

    // Window renaming: headless `window rename`, and the `window prompt` widget
    // opened from the Dofus team submap.
    WindowRename {}

    // Themed which-key keybind cheatsheet. Toggled via IPC.
    CheatSheet {}

    // Passive peek variant: non-focus, non-dimming contextual panel driven by
    // the Hyprland submap event system (hypr/events/peek.lua).
    CheatSheetPeek {}
}
