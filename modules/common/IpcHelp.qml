// Central, human-friendly IPC help. `qs -c quantumfate ipc show` lists raw
// signatures; this adds a curated overview with descriptions and examples:
//
//   qs -c quantumfate ipc call help all
//
// Keep the text in sync when adding IPC targets. The canonical machine-readable
// list is always `ipc show`; this is the annotated companion.
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "help"

        // Full annotated overview of every IPC target.
        function all(): string {
            return [
                "quantumfate quickshell — IPC surface",
                "(raw signatures: `qs -c quantumfate ipc show`)",
                "",
                "help",
                "  all                      This overview.",
                "",
                "theme  — colorscheme (services/Theme.qml)",
                "  get                      Print active palette name.",
                "  set <palette>            Switch palette live (e.g. frappe).",
                "",
                "dofus  — team source of truth (services/DofusState.qml)",
                "  team                     Ordered team member names, one per line.",
                "  selected                 Active team key.",
                "  select <key>             Switch active team (persists to team.json).",
                "  reload                   Re-read team.json from disk now.",
                "",
                "dofusWindows  — team as live windows (services/DofusWindows.qml)",
                "  slots                    name<TAB>present<TAB>address per team slot.",
                "  focus <name>             Focus + raise that character's window.",
                "",
                "dofusSwap  — auto turn-swap detector (services/DofusSwap.qml)",
                "  calibrate                Pick the turn-popup name region (slurp).",
                "  learn <name>             Store <name>'s turn-hash from the region now.",
                "  run | stop               Start/stop the detector for the active team.",
                "  status                   running/stopped + calibrated + learned names.",
                "",
                "bar  — top bar / taskbar (modules/bar/Bar.qml)",
                "  toggleTaskbar | showTaskbar | hideTaskbar   Show/hide the Dofus taskbar.",
                "dofusPanel  — back-compat alias for the taskbar (Dofus submap)",
                "  show | hide | toggle     Repointed onto the taskbar (HUD retired).",
                "",
                "cheatsheet  — keybind overlay (modules/cheatsheet/CheatSheet.qml)",
                "  show | hide | toggle     Which-key list for the active submap.",
                "",
                "window  — window renaming (modules/common/WindowRename.qml)",
                "  rename <title>           Rename the active (XWayland) window's title.",
                "  prompt <pid>             Open the rename widget for a window pid.",
                ""
            ].join("\n");
        }
    }
}
