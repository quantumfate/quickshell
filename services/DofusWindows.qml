pragma Singleton
// DofusWindows — the live view of the Dofus team AS WINDOWS.
//
// DofusState owns the ORDER (team.json, the single source of truth). This
// service joins that order against the compositor's live windows: it matches
// Hyprland toplevels whose title carries the `titlePrefix` ("Dofus <Name>")
// and pairs each team slot with the window currently wearing that name.
//
// The join is recomputed reactively whenever windows open/close/rename/focus
// (Hyprland.toplevels + rawEvent), so any UI over `slots` stays in sync with
// the compositor for free — no window ids are ever stored in state.
//
// Window ACTIONS live here too (focus+raise, rename, close). Reorder is a pure
// state edit, so it stays in DofusState and callers use it directly.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "."   // DofusState, Config singletons

Singleton {
    id: root

    // A team slot resolved against the live compositor. `present`/`focused`
    // reflect the window right now; `address` is Hyprland's handle for actions.
    // (No QML type facility for structs — this documents the `slots` element.)
    //   name: string        the team character name (from team.json order)
    //   index: int          position in the team (0-based)
    //   present: bool       a matching window currently exists
    //   focused: bool       that window is the active one
    //   address: string     Hyprland address ("0x..") or "" when absent
    //   pid: int            window pid, or -1 when absent

    readonly property string titlePrefix: DofusState.titlePrefix

    // The join, recomputed by _rebuild(). One entry per team member, in order.
    property var slots: []

    // Live compositor state we depend on; changes here drive _rebuild().
    // Hyprland.toplevels is an external, mutable model owned by the compositor.
    readonly property var _toplevels: Hyprland.toplevels

    // Recompute whenever the window set changes or any window's title/focus does.
    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { root._rebuild(); }
    }
    Connections {
        target: Hyprland
        // activewindow / title changes arrive as raw events; cheap to rebuild.
        function onRawEvent(event) { root._rebuild(); }
    }
    Connections {
        target: DofusState
        // Rebuild on team switch AND on in-place edits (reorder/rename/add/remove)
        // — the array identity changes, so slots must be recomputed to reflect it.
        function onSelectedChanged() { root._rebuild(); }
        function onTeamChanged() { root._rebuild(); }
    }
    Component.onCompleted: { Hyprland.refreshToplevels(); root._rebuild(); }

    // lastIpcObject (address, workspace, pid) is populated lazily; refresh it so
    // the join can read workspace/pid, not just the title from the event stream.
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: Hyprland.refreshToplevels()
    }

    // Index live Dofus windows by the character name embedded in their title,
    // then walk the team order so slots follow team.json, not window creation.
    function _rebuild() {
        const byName = root._windowsByName();
        const team = DofusState.team || [];
        root.slots = team.map((name, index) => {
            const w = byName[name];
            return {
                name: name,
                index: index,
                present: w !== undefined,
                focused: w !== undefined && w.focused,
                title: w ? w.title : "",
                pid: w ? w.pid : -1
            };
        });
    }

    // Map character-name -> { address, pid, focused } for every window whose
    // title starts with titlePrefix. Later windows win a duplicate name (rare).
    function _windowsByName() {
        const prefix = root.titlePrefix;
        const out = ({});
        const wins = (Hyprland.toplevels?.values) || [];
        for (const w of wins) {
            const ipc = w?.lastIpcObject;
            const title = (ipc?.title) ?? w?.title ?? "";
            if (!title.startsWith(prefix)) continue;
            const name = title.slice(prefix.length).trim();
            if (name.length === 0) continue;
            out[name] = { title: title, pid: ipc?.pid ?? -1, focused: !!w?.activated };
        }
        return out;
    }

    // ---- window actions -----------------------------------------------------

    // Focus a slot's window and raise it — the taskbar's primary gesture.
    // Dofus XWayland toplevels expose no stable address, so we select by title.
    function focus(title) { if (title) Hypr.focus("title:" + title); }

    // Rename a slot: retitle the live window (prefix + name) AND rewrite the name
    // in team.json, keeping the state<->window join stable.
    function rename(index, pid, newName) {
        const name = (newName || "").trim();
        if (name.length === 0 || index < 0) return;
        Hypr.retitle(pid, root.titlePrefix + name);
        DofusState.rename(index, name);
    }

    // Close a slot's window by title. State is left untouched (slot stays,
    // now present:false), so the roster is unaffected by a closed window.
    function close(title) { if (title) Hypr.close("title:" + title); }

    // Present slots in team order — the roster the taskbar and cycling act on.
    function _present() { return (root.slots || []).filter(s => s.present); }

    // Workspace ids that currently hold team windows — so a bar can hide the
    // Dofus taskbar when its monitor isn't showing the team (the model, not the
    // view, decides where the team "is"). Sourced from hyprctl: Quickshell
    // mis-maps XWayland toplevels' workspace (returns -1), so we ask directly.
    property var teamWorkspaceIds: []
    Process {
        id: wsProbe
        command: ["bash", "-lc",
            "hyprctl clients -j | jq -c '[.[] | select(.class==\"Dofus.x64\") | .workspace.id] | unique'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.teamWorkspaceIds = JSON.parse((this.text || "[]").trim()); }
                catch (e) { root.teamWorkspaceIds = []; }
            }
        }
    }
    Timer {
        interval: 1500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!wsProbe.running) wsProbe.running = true;
    }

    // Is the given workspace id one the team is on right now?
    function onWorkspace(wsId) {
        return wsId !== undefined && root.teamWorkspaceIds.indexOf(wsId) !== -1;
    }

    // Focus the next/previous PRESENT window in team (turn) order, wrapping.
    // This is the join-aware version of the old Lua `iterate`: the UI already
    // owns name<->window<->focus, so callers need no hyprctl querying.
    function cycle(reversed) {
        const present = root._present();
        if (present.length === 0) return;
        const at = present.findIndex(s => s.focused);
        const n = present.length;
        const next = at < 0 ? 0 : (reversed ? (at - 1 + n) % n : (at + 1) % n);
        root.focus(present[next].title);
    }

    // Focus+raise the team member at a 0-based team index (no-op if absent).
    function activate(index) {
        const s = (root.slots || [])[index];
        if (s && s.present) root.focus(s.title);
    }

    // ---- scripting surface: qs -c quantumfate ipc call dofusWindows <fn> ----
    IpcHandler {
        target: "dofusWindows"
        // Ordered "name<TAB>present<TAB>address" lines for external tools.
        function slots(): string {
            return (root.slots || [])
                .map(s => [s.name, s.present ? "1" : "0", s.title].join("\t"))
                .join("\n");
        }
        function focus(name: string): void {
            const s = (root.slots || []).find(x => x.name === name);
            if (s) root.focus(s.title);
        }
        // Turn-order navigation, offloaded from the Hyprland config.
        function next(): void { root.cycle(false); }
        function prev(): void { root.cycle(true); }
        function activate(index: int): void { root.activate(index); }
    }
}
