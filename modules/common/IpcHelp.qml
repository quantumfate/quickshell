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
                "dofusPanel  — team HUD window (modules/dofus/DofusTeam.qml)",
                "  show | hide | toggle     Control the panel. Driven by the Dofus submap.",
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
