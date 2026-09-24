pragma Singleton
// ProjectWindows — which projects are open, and which one you are in.
//
// A project is a set of kitty windows classed `Proj-<name>` in one Hyprland
// group on the `code` scene (hyprrepo bin/,proj.sh). There is no state file to
// read: a project exists exactly as long as its windows do, so the compositor
// is the only source, the same way DofusWindows treats the Dofus group.
//
// This is a read model over `hyprctl clients -j`, grouped by project name and
// published as one entry per PROJECT rather than per window — the bar shows
// projects, and a project's tabs are reached with its own keys. Focus is
// applied from `activewindowv2` on the spot rather than waiting for a poll, so
// the highlight keeps up with the keyboard.
//
// No window ids are stored in state, and a project's selector is rebuilt from
// the live snapshot every time.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "ProjectWindows.js" as Lib

Singleton {
    id: root

    // One entry per open project:
    //   name: string       the project's own name ("hypr"), class minus the prefix
    //   windowClass: string  the full class ("Proj-hypr")
    //   addresses: string[]  every live window of it
    //   selector: string   "address:0x…" for the window a click should focus
    //   slots: string[]    the roles live right now ("nvim", "yazi", …)
    //   focused: bool      one of its windows holds the keyboard
    property var projects: []

    readonly property string classPrefix: "Proj-"
    // `Proj-picker` and `Proj-confirm` wear the project class prefix so the
    // scene floats them as strays, but they are prompts, not projects.
    readonly property var notAProject: ["picker", "confirm"]

    property string activeAddress: ""

    readonly property var focusedProject: {
        for (let i = 0; i < root.projects.length; i++)
            if (root.projects[i].focused) return root.projects[i];
        return null;
    }

    function _normalize(addr) { return Lib.normalize(addr); }

    // Repaint `focused` from a focus event, without waiting for a snapshot.
    // A focus that landed outside every project clears the highlight rather
    // than leaving a stale one lit.
    function _updateFocused(addr) {
        if (!root.projects || root.projects.length === 0) return;
        const norm = root._normalize(addr);
        let changed = false;
        const next = root.projects.map(p => {
            const f = p.addresses.indexOf(norm) !== -1;
            if (p.focused !== f) { changed = true; return Object.assign({}, p, { focused: f }); }
            return p;
        });
        if (changed) root.projects = next;
    }

    // ── the snapshot pipeline ───────────────────────────────────────────────
    Process {
        id: snap
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector { onStreamFinished: root._applyClients(this.text || "") }
        stderr: StdioCollector {}
        onExited: {
            if (root._pendingSnap) { root._pendingSnap = false; snap.running = true; }
        }
    }

    property bool _pendingSnap: false
    function _requestSnap() {
        if (snap.running) { root._pendingSnap = true; return; }
        root._pendingSnap = false;
        snap.running = true;
    }

    // The slow poll is the discovery fallback: a project already open when the
    // shell starts emits no `openwindow`. Structural events carry everything
    // after that, so this stays slow on purpose.
    Timer {
        interval: 10000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root._requestSnap()
    }
    Timer {
        id: eventDebounce
        interval: 50; repeat: false
        onTriggered: root._requestSnap()
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindowv2") {
                root.activeAddress = root._normalize(event.data);
                root._updateFocused(root.activeAddress);
                return;
            }
            if (event.name === "openwindow" || event.name === "closewindow"
                || event.name === "movewindow" || event.name === "movewindowv2") {
                eventDebounce.restart();
            }
        }
    }

    function _applyClients(text) {
        let clients = [];
        try { clients = JSON.parse(text) || []; }
        catch (e) { return; }   // a truncated snapshot is dropped; the next poll repairs it
        root.projects = Lib.group(clients, root.activeAddress);
    }

    // Focus a project: its last-focused window, or its first.
    function focus(name) {
        for (const p of root.projects) {
            if (p.name === name) { Hypr.focus(p.selector); return; }
        }
    }
}
