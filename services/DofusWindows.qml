pragma Singleton
// DofusWindows — the live view of the Dofus group.
//
// DofusState owns the ORDER (team.json, the single source of truth). This
// service owns the live WINDOWS: it lists the Hyprland group's members the way
// the groupbar shows them — one entry per window, in group membership order —
// and which member is focused. LEO-230 moved iteration into Hyprland
// (hl.dsp.group.next/prev), so this service no longer drives navigation; it is
// a read model over the group plus the window actions that still have logic
// behind them (focus, iterate, close the group, assign/clear a name, rename a
// character).
//
// The model is a SNAPSHOT, rebuilt from `hyprctl clients -j` on a poll plus a
// debounced copy of Hyprland's raw events (open/close/title/focus moves it
// within 200ms). No Quickshell-side toplevel fields are trusted: refreshToplevels
// leaves lastIpcObject `{}` on this runtime (the Lua dispatch bridge — see
// hyprrepo ARCHITECTURE.md), so class/membership/geometry all come from the
// compositor's own JSON. No window ids are ever stored in state.
import Quickshell
import Quickshell.Io
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
    //   grouped: string[]   the whole group's address list (membership order)
    //   at / size: point    the tile's global geometry (all members share it)
    //   workspaceId / workspaceName / monitorId: where the tile lives
    property var windows: []

    readonly property string titlePrefix: DofusState.titlePrefix
    readonly property string _dofusClass: "Dofus.x64"

    // ── the snapshot pipeline ───────────────────────────────────────────────
    // One `hyprctl clients -j` fetch, parsed into `windows`. Polling keeps the
    // model warm; events make it feel instant.
    Process {
        id: snap
        command: ["sh", "-c", "hyprctl clients -j"]
        stdout: StdioCollector { onStreamFinished: root._applyClients(this.text || "") }
        stderr: StdioCollector {}
    }

    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: snap.running = true
    }
    // Event debounce: many raw events coalesce into one fetch.
    Timer {
        id: eventDebounce
        interval: 200; repeat: false
        onTriggered: snap.running = true
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { eventDebounce.restart(); }
    }

    function _applyClients(text) {
        const prefix = root.titlePrefix;
        let clients = [];
        try { clients = JSON.parse(text) || []; }
        catch (e) { return; }   // a truncated/unparsable snapshot is just dropped; the next poll repairs it

        const byAddr = {};
        for (const c of clients) {
            if (c?.class !== root._dofusClass) continue;
            const address = c?.address ?? "";
            if (!address) continue;   // un-addressable windows can't be grouped or acted on
            const title = c?.title ?? "";
            byAddr[address] = {
                name: title.startsWith(prefix) ? title.slice(prefix.length).trim() : "",
                title: title,
                pid: c?.pid ?? -1,
                address: address,
                selector: "address:" + address,
                grouped: c?.grouped ?? [],
                // Internal fullscreen bitmask (0 none, 1 fullscreen, 2
                // maximize, 3 both) — Hypr hides its own bar when a member
                // renders fullscreen, and the widget must follow (LEO-243).
                fullscreen: c?.fullscreen ?? 0,
                at: { x: c?.at?.[0] ?? 0, y: c?.at?.[1] ?? 0 },
                size: { x: c?.size?.[0] ?? 0, y: c?.size?.[1] ?? 0 },
                workspaceId: c?.workspace?.id ?? -1,
                workspaceName: c?.workspace?.name ?? "",
                // hyprctl reports the monitor by numeric id, not name.
                monitorId: c?.monitor ?? -1,
                focusHistoryID: c?.focusHistoryID ?? -1,
            };
        }

        const members = Object.values(byAddr);
        // The group's active tab is its most-recently-focused member (highest
        // focus history id). With no membership this degenerates to "any".
        let recent = -1;
        for (const w of members) if (w.focusHistoryID > recent) recent = w.focusHistoryID;
        for (const w of members) w.focused = w.focusHistoryID === recent;

        // Group order comes from a member's own `grouped` list (the whole
        // group, itself included); while it is missing, fall back to report
        // order so the model never goes empty.
        const out = [];
        const seen = {};
        const push = (addr) => {
            const w = byAddr[addr];
            if (!w || seen[addr]) return;
            seen[addr] = true;
            out.push(w);
        };
        let order = [];
        for (const w of members) {
            if (w.grouped && w.grouped.length > 0) { order = w.grouped; break; }
        }
        if (order.length > 0) for (const addr of order) push(addr);
        for (const addr of Object.keys(byAddr)) push(addr);

        root.windows = out;
    }

    // ---- window actions -----------------------------------------------------

    // Focus a window by its selector ("address:0x…") and raise it — the Active
    // Windows zone's primary gesture.
    function focus(selector) { if (selector) Hypr.focus(selector); }

    // Close a window by selector. Team state is untouched (a closed team slot
    // just goes absent); a separate window simply disappears.
    function close(selector) { if (selector) Hypr.close(selector); }

    // Rename a window: retitle it (prefix + name). For a named team member
    // (index >= 0) also rewrite team.json so the join stays stable; for an
    // un-named client (index < 0) it is just a retitle — which, if the new
    // name is a team member, makes the window join that character's slot.
    function rename(index, pid, newName) {
        const name = (newName || "").trim();
        if (name.length === 0 || !(pid > 0)) return;
        Hypr.retitle(pid, root.titlePrefix + name);
        if (index >= 0) DofusState.rename(index, name);
    }

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
