//@ pragma UseQApplication
// Root shell config. Loaded by: qs -c quantumfate  (or -p /path/to/shell.qml)
// Each top-level widget is a Scope/window. Add bars, notifications, etc. here.
import Quickshell
import "modules/common"
import "modules/cheatsheet"
import "modules/bar"
import "modules/dofus"
import "modules/obsidian"
import "modules/control"
import "modules/whichkey"

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

    // Dofus team selector: pick the active team from a list. Opened via the
    // Dofus submap or IPC.
    TeamSelector {}

    // Dofus class assigner: bind each character to a class (standalone from the
    // team panel). Opened via the Dofus submap or IPC.
    ClassAssigner {}

    // Obsidian new-note form: type/title/topic + index-chain preview over the
    // ObsidianVault store. Opened via the Obsidian submap or IPC.
    ObsidianCreate {}

    // Themed which-key keybind cheatsheet. Toggled via IPC.
    CheatSheet {}

    // Which-key overlay (LEO-222 / LEO-327): the SUPER-Space leader's tree
    // renderer. It mirrors the submap stack automatically after a short dwell,
    // so no binding action ever needs to open it — the Lua side only ever tells
    // it to dismiss.
    // mirrors the submap stack automatically, so no binding action ever needs
    // to open it — the Lua side only ever tells it to dismiss.
    WhichKey {}

    // Keyboard-first workspace switcher: type to filter, enter to go, shift+enter
    // to bring the focused window along. Toggled via IPC.
    WorkspaceSwitcher {}

    // Detail panels behind the bar's projects/calendar pills, driven by
    // modules/bar/PanelBus.
    ProjectsDashboard {}
    CalendarPanel {}
    MoodPanel {}

    // Control Centre: theme/appearance/wallpaper/sound/focus, one panel over
    // backends that otherwise have no UI. Toggled via IPC.
    ControlPanel {}
    SystemCenter {}
}
