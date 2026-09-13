pragma Singleton
// Focus mode: a Store plus the enforcement seam, not the UI.
//
// Firm semantics — refuse, with an explicit override, never tear down a
// session already running. `canLaunch`/`blockReason` are read at DISPATCH
// time by whatever launches a media browser or a game (an IPC call from a
// script, not a compiled-in bind check), so leaving focus mode needs no
// Hyprland reload: the next launch attempt just sees `mode == "off"`.
//
// This file owns the data and the yes/no; it does not enforce anything by
// itself. See ARCHITECTURE.md and the task report for what still needs to
// call into it (media browser + game launcher scripts, DND, the media
// workspace's reachability) — none of those are this repo's files.
import Quickshell
import Quickshell.Io
import QtQuick
import "."

Singleton {
    id: root

    Store {
        id: store
        name: "focus"
        defaults: ({ mode: "off", until: null })
    }

    readonly property string mode: store.get("mode") ?? "off"
    readonly property var until: store.get("until") ?? null

    // Live even past `until`: a stale "focus" that nothing has cleared yet
    // should stop blocking on its own rather than wait for the next `stop()`.
    readonly property bool active: root.mode === "focus" &&
        (root.until === null || Date.now() < Date.parse(root.until))

    // Kinds firm focus blocks. Anything else (a terminal, an editor) is
    // untouched — this takes options away, it does not lock the desk down.
    readonly property var blockedKinds: (["media", "game"])

    function canLaunch(kind) { return !(root.active && root.blockedKinds.indexOf(kind) >= 0); }

    function blockReason(kind) {
        if (root.canLaunch(kind)) return "";
        const until = root.until ? (" until " + root.until) : "";
        return "focus mode is on" + until + " — this is blocked while it runs";
    }

    // `minutes` <= 0 means open-ended (only `stop()` ends it).
    function start(minutes) {
        const until = (minutes && minutes > 0)
            ? new Date(Date.now() + minutes * 60000).toISOString()
            : null;
        store.set({ mode: "focus", until: until });
    }

    // The explicit override: the only way out of an open-ended session, and
    // the deliberate early exit from a timed one.
    function stop() { store.set({ mode: "off", until: null }); }

    // ipc: qs -c quantumfate ipc call focus <fn>
    IpcHandler {
        target: "focus"
        function status(): string {
            return root.mode + (root.until ? (" until " + root.until) : "");
        }
        function start(minutes: int): void { root.start(minutes); }
        function stop(): void { root.stop(); }
        // "yes" / "no: <reason>" — a launcher script greps the first word.
        function canLaunch(kind: string): string {
            return root.canLaunch(kind) ? "yes" : ("no: " + root.blockReason(kind));
        }
        function reload(): void { store.reload(); }
    }
}
