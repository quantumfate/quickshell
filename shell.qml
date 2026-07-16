//@ pragma UseQApplication
// Root shell config. Loaded by: qs -c quantumfate  (or -p /path/to/shell.qml)
// Each top-level widget is a Scope/window. Add bars, notifications, etc. here.
import Quickshell
import "modules/common"
import "modules/dofus"
import "modules/cheatsheet"

ShellRoot {
    // `qs -c quantumfate ipc call help all` — annotated IPC overview.
    IpcHelp {}

    // `qs -c quantumfate ipc call window rename "..."` — rename focused window.
    WindowIpc {}

    // Dofus team HUD + editor. Toggled via IPC / Hyprland submap.
    DofusTeam {}

    // Themed which-key keybind cheatsheet. Toggled via IPC.
    CheatSheet {}
}
