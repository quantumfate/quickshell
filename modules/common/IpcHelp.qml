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
                "dofusSwap  — auto turn-swap detector (services/DofusSwap.qml)",
                "  calibrate                Pick the turn-popup name region (slurp).",
                "  learn <name>             Store <name>'s turn-hash from the region now.",
                "  run | stop               Start/stop the detector for the active team.",
                "  status                   running/stopped + calibrated + learned names.",
                "",
                "bar  — top bar (modules/bar/Bar.qml)",
                "  reveal                   Drop every bar out of autohide.",
                "cheatsheet  — keybind overlay (modules/cheatsheet/CheatSheet.qml)",
                "  show | hide | toggle     Which-key list for the active submap.",
                "",
                "whichkey  — SUPER-Space leader overlay (modules/whichkey/WhichKey.qml)",
                "  dismiss                  Close it (raised by submap.lua on tree exit).",
                "  show | hide | toggle     Manual open/close; it normally follows submaps.",
                "",
                "groupMenu  — Dofus group quick actions (modules/dofus/GroupBar.qml)",
                "  show | hide | toggle     quick-actions menu: focus members, cycle the",
                "                           group, open the team/class panels, close all.",
                "",
                "obsidian  — vault store + actions (services/ObsidianVault.qml)",
                "  status                   Vault, note/topic counts, last sync.",
                "  tree                     Indented tag-tree report.",
                "  create <type> <title> <tag>   Create a note (type: atomic|fleeting|moc|journal|blog).",
                "  ensure <topic>           Create the missing idx/meta_idx chain.",
                "  lastTopic                Topic the create form last used.",
                "  setOpenOnCreate <true|false>   Whether create passes --open (persisted).",
                "",
                "obsidianCreate  — new-note form (modules/obsidian/ObsidianCreate.qml)",
                "  show | hide | toggle     Open the create-note popup. The bind (toggle)",
                "                          closes the popup and aborts a running create;",
                "                          clicking the dimmed area does NOT close it.",
                "  Note: call with `ipc call -- <target> <fn>` — the CLI treats",
                "  a function named 'show' as the 'ipc show' subcommand otherwise.",
                "",
                "window  — window renaming (modules/common/WindowRename.qml)",
                "  rename <title>           Rename the active (XWayland) window's title.",
                "  prompt <pid>             Open the rename widget for a window pid.",
                ""
            ].join("\n");
        }
    }
}
