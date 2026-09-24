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
// The model is a SNAPSHOT, rebuilt from `hyprctl clients -j` on a slow poll
// plus a debounced copy of Hyprland's structural events (open/close/title/
// move). FOCUS is the exception: `activewindowv2` names the active window
// directly and is applied to the published list on the spot, so the roster's
// highlight never waits on a poll. No Quickshell-side toplevel fields are
// trusted: refreshToplevels leaves lastIpcObject `{}` on this runtime (the Lua
// dispatch bridge — see hyprrepo ARCHITECTURE.md), so class/membership/geometry
// all come from the compositor's own JSON. No window ids are ever stored in
// state.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "."   // DofusState, Config singletons
import "DofusFocus.js" as DofusFocus   // the pure focus resolution

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
    //   workspaceAddress / workspaceName / monitorId: where the tile lives
    property var windows: []

    // The compositor's live focus ("0x…"), and the last Dofus member that held
    // it — the two inputs to which tab the roster marks. See DofusFocus.js for
    // the resolution and why `focusHistoryID` is read the way it is.
    property string activeAddress: ""
    property string _lastDofusAddress: ""

    readonly property string titlePrefix: DofusState.titlePrefix
    readonly property string _dofusClass: "Dofus.x64"

    // Repaint the published list's `focused` flag from the live focus, without
    // waiting for a snapshot. Focus is one event hop away instead of one poll.
    function _updateFocused(addr) {
        if (!root.windows || root.windows.length === 0) return;
        const norm = DofusFocus.normalize(addr);
        const isDofus = root.windows.some(w => DofusFocus.normalize(w.address) === norm);
        if (!isDofus) return;
        root._lastDofusAddress = norm;
        let changed = false;
        const next = root.windows.map(w => {
            const f = (DofusFocus.normalize(w.address) === norm);
            if (w.focused !== f) {
                changed = true;
                return Object.assign({}, w, { focused: f });
            }
            return w;
        });
        if (changed) root.windows = next;
    }

    // ── the snapshot pipeline ───────────────────────────────────────────────
    // One `hyprctl clients -j` fetch, parsed into `windows`. Polling keeps the
    // model warm; structural events make it keep up. Focus never waits for it
    // (see the `activewindowv2` handler below).
    Process {
        id: snap
        // Called directly, not through `sh -c`: one less fork for the fetch
        // that runs on every structural event.
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector { onStreamFinished: root._applyClients(this.text || "") }
        stderr: StdioCollector {}
        // A request that arrived while a fetch was in flight runs the moment
        // the slot frees — coalesced into exactly one extra fetch, never a
        // queue of them.
        onExited: {
            if (root._pendingSnap) {
                root._pendingSnap = false;
                snap.running = true;
            }
        }
    }

    property bool _pendingSnap: false
    function _requestSnap() {
        if (snap.running) { root._pendingSnap = true; return; }
        root._pendingSnap = false;
        snap.running = true;
    }

    // Fast poll only while there is a Dofus group to keep current; the slow
    // poll is the discovery fallback (a client already running when the shell
    // starts emits no `openwindow`), so a desk with no Dofus running pays two
    // `hyprctl` reads a minute instead of thirty (LEO-424).
    Timer {
        interval: 2000
        running: root.windows.length > 0
        repeat: true
        onTriggered: root._requestSnap()
    }
    Timer {
        interval: 10000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root._requestSnap()
    }
    // Structural-event debounce. Short, because the event already said
    // something changed and the fetch is a plain `hyprctl` read; the debounce
    // only folds a burst (a group opening eight clients at once) into one fetch.
    Timer {
        id: eventDebounce
        interval: 50; repeat: false
        onTriggered: root._requestSnap()
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Focus is applied immediately from the event's own payload: the
            // address it carries is the compositor's answer, so the highlight
            // is one event hop away instead of one poll.
            if (event.name === "activewindowv2") {
                root.activeAddress = DofusFocus.normalize(event.data);
                root._updateFocused(root.activeAddress);
                return;
            }
            if (event.name === "openwindow" || event.name === "closewindow"
                || event.name === "movewindow" || event.name === "movewindowv2"
                || event.name === "windowtitle" || event.name === "changefloatingmode"
                || event.name === "fullscreen") {
                eventDebounce.restart();
            }
        }
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
                // A client's workspace is `{ address, type, name }` — there
                // is no `id` field (verified against this Hyprland's own
                // `hyprctl clients -j`). Reading one yielded `undefined` on
                // every window, which is how the roster isle's "are any Dofus
                // clients on the workspace I am showing" test could never be
                // true. `name` is the join every other consumer here already
                // uses (scene names, window rules, dispatch targets), so it is
                // the one this model publishes; `address` rides along as the
                // compositor's own handle for a named workspace.
                workspaceAddress: c?.workspace?.address ?? "",
                workspaceName: c?.workspace?.name ?? "",
                // hyprctl reports the monitor by numeric id, not name.
                monitorId: c?.monitor ?? -1,
                focusHistoryID: c?.focusHistoryID ?? -1,
            };
        }

        const members = Object.values(byAddr);

        // The active tab comes from the compositor's own focus, never a
        // recomputed guess. The live `activewindowv2` address is
        // authoritative; the snapshot's focus history is only the seed for the
        // first poll, before any event has arrived.
        const active = root.activeAddress || DofusFocus.activeFromHistory(clients);

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

        // Mark the active tab. DofusFocus.focusedAddress carries the rule: a
        // focused member wins, the last member that held focus stands in while
        // the group is unfocused, and an unfocused-from-birth group still
        // reads as one group.
        const focusAddr = DofusFocus.focusedAddress(active, root._lastDofusAddress, out);
        for (const w of out) w.focused = DofusFocus.normalize(w.address) === focusAddr;
        if (focusAddr) root._lastDofusAddress = focusAddr;

        // Rebuilding the array re-creates every Repeater delegate in the
        // roster — it visibly re-lays-out and drops hover/focus state. Publish
        // only when the shape actually changed, so a poll that learned nothing
        // new is invisible.
        if (!root._sameWindows(root.windows, out)) root.windows = out;
    }

    // Shallow structural equality over the published fields, for the poll
    // above: a snapshot that changed nothing must not churn the delegates.
    function _sameWindows(a, b) {
        if (!a || !b || a.length !== b.length) return false;
        for (let i = 0; i < a.length; i++) {
            const x = a[i], y = b[i];
            if (x.address !== y.address || x.title !== y.title || x.pid !== y.pid
                || x.name !== y.name || x.focused !== y.focused
                || x.workspaceName !== y.workspaceName
                || x.workspaceAddress !== y.workspaceAddress
                || x.monitorId !== y.monitorId || x.fullscreen !== y.fullscreen
                || x.at.x !== y.at.x || x.at.y !== y.at.y
                || x.size.x !== y.size.x || x.size.y !== y.size.y
                || x.grouped.join(",") !== y.grouped.join(",")) return false;
        }
        return true;
    }

    // ---- window actions -----------------------------------------------------

    // Focus a window by its selector ("address:0x…") and raise it — the Active
    // Windows zone's primary gesture.
    function focus(selector) { if (selector) Hypr.focus(selector); }

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
