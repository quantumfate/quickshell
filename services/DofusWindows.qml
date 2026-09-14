pragma Singleton
// DofusWindows — the live view of the Dofus group.
//
// DofusState owns the ORDER (team.json, the single source of truth). This
// service owns the live WINDOWS: it lists the Hyprland group's members the way
// the groupbar shows them — one entry per window, in group membership order —
// and which member is focused. LEO-230 moved iteration into Hyprland
// (hl.dsp.group.next/prev), so this service no longer drives navigation; it is
// a read model over the group plus the window actions that still have logic
// behind them (focus, assign/clear a name, rename a character).
//
// The model is recomputed reactively whenever windows open/close/rename/focus
// (Hyprland.toplevels + rawEvent), backed by a periodic IPC refresh so
// `grouped` membership is available — no window ids are ever stored in state.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import "."   // DofusState, Config singletons

Singleton {
    id: root

    // The group's live members, in group order (same thing the groupbar
    // shows). Each entry is a live Dofus.x64 window:
    //   name: string        character name parsed from the title ("Dofus <Name>"),
    //                       "" while the window is unnamed
    //   title: string       raw window title
    //   pid: int            window pid, or -1 when absent
    //   address: string     Hyprland address ("0x..") or "" when absent
    //   selector: string    the stable "address:0x…" used for actions
    //   focused: bool       that window is the group's active tab
    property var windows: []

    readonly property string titlePrefix: DofusState.titlePrefix

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
    Component.onCompleted: { Hyprland.refreshToplevels(); root._rebuild(); }

    // lastIpcObject (address, pid, grouped) is populated lazily; refresh it so
    // the model can read the group membership, not just the title from the
    // event stream.
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: Hyprland.refreshToplevels()
    }

    // Recompute the roster from the live Dofus windows, in group order. The
    // group's member order comes from any window's `grouped` IPC field (the
    // address list of the whole group, itself included); while that is still
    // warming up it falls back to the list order.
    function _rebuild() {
        const byAddr = root._dofusWindows();

        const out = [];
        const seen = ({});
        const push = (addr) => {
            const w = byAddr[addr];
            if (!w || seen[addr]) return;
            seen[addr] = true;
            out.push(w);
        };

        let order = [];
        for (const addr of Object.keys(byAddr)) {
            const grouped = byAddr[addr].grouped;
            if (grouped && grouped.length > 0) { order = grouped; break; }
        }
        if (order.length > 0) for (const addr of order) push(addr);
        for (const addr of Object.keys(byAddr)) push(addr);

        root.windows = out;
    }

    // Every live Dofus window, keyed by address. Matched STRICTLY by window
    // class (Dofus.x64) — never by title, so unrelated windows that merely
    // carry "Dofus" in their title (a browser tab, an editor) are excluded.
    // `name` is "" for an un-named window.
    function _dofusWindows() {
        const prefix = root.titlePrefix;
        const byAddr = ({});
        const wins = (Hyprland.toplevels?.values) || [];
        for (const w of wins) {
            const ipc = w?.lastIpcObject;
            const cls = (ipc?.class) ?? "";
            if (cls !== "Dofus.x64") continue;
            const title = (ipc?.title) ?? w?.title ?? "";
            const address = ipc?.address ?? "";
            if (!address) continue;   // un-addressable windows can't be grouped or acted on
            byAddr[address] = {
                name: title.startsWith(prefix) ? title.slice(prefix.length).trim() : "",
                title: title,
                pid: ipc?.pid ?? -1,
                address: address,
                selector: "address:" + address,
                focused: !!w?.activated,
                grouped: ipc?.grouped ?? ([]),
                // Geometry and placement, straight off `hyprctl clients`
                // (at/size are [x,y] arrays there). These feed the group widget's
                // position above the tile — never stored outside this rebuild.
                at: { x: ipc?.at?.[0] ?? 0, y: ipc?.at?.[1] ?? 0 },
                size: { x: ipc?.size?.[0] ?? 0, y: ipc?.size?.[1] ?? 0 },
                workspaceId: ipc?.workspace?.id ?? -1,
                workspaceName: ipc?.workspace?.name ?? "",
                monitor: ipc?.monitor ?? "",
            };
        }
        return byAddr;
    }

    // ---- window actions -----------------------------------------------------

    // Focus a window by its selector ("address:0x…") and raise it — the Active
    // Windows zone's primary gesture.
    function focus(selector) { if (selector) Hypr.focus(selector); }

    // Step the group's active tab one place (hl.dsp.group.next/prev — the
    // compositor primitives LEO-230 established; no iteration is stored here).
    // Group dispatches act on the FOCUSED window, so a group where focus has
    // drifted elsewhere is re-seeded on its first member before stepping.
    function iterate(reversed) {
        const members = root.windows || [];
        if (members.length === 0) return;
        if (!(members.some(w => w.focused)))
            root.focus(members[0].selector);
        Hyprland.dispatch(reversed ? "hl.dsp.group.prev()" : "hl.dsp.group.next()");
    }

    // Close every member — the group is the session, so closing the group is
    // closing each live client. Selector-guarded; a member that already left
    // between the model build and its dispatch just no-ops.
    function closeAll() {
        for (const w of (root.windows || []))
            if (w.selector) Hypr.close(w.selector);
    }

    // Assign a character name to a live window: retitle it (prefix + name). If
    // the name is a team member, the window joins that character the moment any
    // UI rebuilds — state (team.json) is untouched.
    function setName(pid, name) {
        const n = (name || "").trim();
        if (pid > 0 && n.length > 0) Hypr.retitle(pid, root.titlePrefix + n);
    }

    // Clear a window's character name (mark it "unnamed"): retitle to the bare
    // prefix, so it drops out of every character on the next rebuild.
    function clearName(pid) {
        if (pid > 0) Hypr.retitle(pid, root.titlePrefix.trim());
    }

    // Retitle any live window wearing `oldName`, keeping its character match
    // after a pool/team character rename. State is rewritten by
    // DofusState.renameCharacter.
    function renameCharacter(oldName, newName) {
        const n = (newName || "").trim();
        if (!n) return;
        for (const w of (root.windows || [])) {
            if (w.name === oldName && w.pid > 0) Hypr.retitle(w.pid, root.titlePrefix + n);
        }
        DofusState.renameCharacter(oldName, newName);
    }
}