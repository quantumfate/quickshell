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
    //   …plus address:string (Hyprland handle) and selector:string (the stable
    //   "address:0x…"/"title:…" used for actions) and team:bool.
    property var slots: []

    // Open Dofus.x64 windows that match NO team slot — e.g. a freshly launched
    // window still titled "Dofus" (no character), or one named outside the team.
    // Same shape as a slot (index:-1, team:false) so the taskbar can show them
    // as generic chips you can focus / close / rename.
    property var unmatched: []

    // What the Dofus taskbar on a given workspace renders: present team windows
    // then unmatched ones, both limited to `wsId` (special workspaces already
    // carry negative ids, so they never match a real workspace and drop out).
    // Reactive via slots/unmatched, so chips track window open/close/move/rename.
    function taskbarOn(wsId) {
        // On this (real, non-special) workspace only. Special workspaces carry
        // negative ids, so `ws >= 0 && ws === wsId` drops them outright.
        const here = w => w.ws >= 0 && w.ws === wsId;
        if (!(wsId >= 0)) return [];
        return slots.filter(s => s.present && here(s)).concat(unmatched.filter(here));
    }

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

    // Join the live Dofus windows against the team order (slots), then collect
    // whatever's left over as `unmatched` generic chips.
    function _rebuild() {
        const wins = root._dofusWindows();
        const byName = ({});
        for (const w of wins) if (w.name) byName[w.name] = w;

        const team = DofusState.team || [];
        const claimed = ({});
        root.slots = team.map((name, index) => {
            const w = byName[name];
            if (w) claimed[w.key] = true;
            return {
                name: name, index: index,
                present: w !== undefined,
                focused: w !== undefined && w.focused,
                title: w ? w.title : "",
                pid: w ? w.pid : -1,
                address: w ? w.address : "",
                selector: w ? w.selector : "",
                ws: w ? w.ws : -1,
                team: true
            };
        });

        root.unmatched = wins.filter(w => !claimed[w.key]).map(w => ({
            // Show "unnamed" rather than exposing the raw "Dofus" placeholder.
            name: w.name || "unnamed",
            index: -1,
            present: true,
            focused: w.focused,
            title: w.title,
            pid: w.pid,
            address: w.address,
            selector: w.selector,
            ws: w.ws,
            focusHistoryId: w.focusHistoryId,
            team: false
        }));
    }

    // Every live Dofus window, matched STRICTLY by window class (Dofus.x64) —
    // never by title, so unrelated windows that merely carry "Dofus" in their
    // title (a browser tab, an editor) are excluded. `name` is "" for an
    // un-titled window; `selector` prefers the stable address, falling back to
    // the title; `key` de-dupes a window across the slot/unmatched split.
    function _dofusWindows() {
        const prefix = root.titlePrefix;
        const out = [];
        const wins = (Hyprland.toplevels?.values) || [];
        for (const w of wins) {
            const ipc = w?.lastIpcObject;
            const cls = (ipc?.class) ?? "";
            const title = (ipc?.title) ?? w?.title ?? "";
            if (cls !== "Dofus.x64") continue;
            const name = title.startsWith(prefix) ? title.slice(prefix.length).trim() : "";
            const address = ipc?.address ?? "";
            out.push({
                name: name, title: title, pid: ipc?.pid ?? -1,
                address: address,
                selector: address ? ("address:" + address) : ("title:" + title),
                focused: !!w?.activated,
                // Hyprland's recency rank (0 = most-recently focused); used to
                // order the unmatched windows when cycling past the team.
                focusHistoryId: ipc?.focusHistoryID ?? 999999,
                // Workspace from the hyprctl probe (Quickshell's own value is
                // unreliable for XWayland); -1 until the probe has seen it.
                ws: (address in root.wsByAddress) ? root.wsByAddress[address] : -1,
                key: address || (title + "#" + (ipc?.pid ?? -1))
            });
        }
        return out;
    }

    // ---- window actions -----------------------------------------------------

    // Focus a window by its selector ("address:0x…"/"title:…") and raise it —
    // the taskbar's primary gesture. Address disambiguates same-titled windows
    // (e.g. several un-named "Dofus" windows).
    function focus(selector) { if (selector) Hypr.focus(selector); }

    // Rename a window: retitle the live window (prefix + name). For a real team
    // slot (index>=0) also rewrite team.json so the join stays stable; for an
    // unmatched window (index<0) it's just a retitle — which, if the new name is
    // a team member, makes the window join that slot on the next rebuild.
    function rename(index, pid, newName) {
        const name = (newName || "").trim();
        if (name.length === 0) return;
        Hypr.retitle(pid, root.titlePrefix + name);
        if (index >= 0) DofusState.rename(index, name);
    }

    // Retitle a live window to `prefix + name` WITHOUT touching team.json — the
    // Active Windows zone's "assign a name" gesture. If the name is a team
    // member, the window joins that slot on the next rebuild.
    function setName(pid, name) {
        const n = (name || "").trim();
        if (pid > 0 && n.length > 0) Hypr.retitle(pid, root.titlePrefix + n);
    }

    // Clear a window's character name (mark it "unnamed"): retitle to the bare
    // prefix, so it drops out of every team slot on the next rebuild.
    function clearName(pid) {
        if (pid > 0) Hypr.retitle(pid, root.titlePrefix.trim());
    }

    // Retitle any present window wearing `oldName`, keeping it matched after a
    // pool/team character rename. State is rewritten by DofusState.renameCharacter.
    function renameCharacter(oldName, newName) {
        const n = (newName || "").trim();
        if (!n) return;
        for (const s of (root.slots || []).concat(root.unmatched || [])) {
            if (s.present && s.name === oldName && s.pid > 0) Hypr.retitle(s.pid, root.titlePrefix + n);
        }
        DofusState.renameCharacter(oldName, newName);
    }

    // Close a window by selector. Team state is left untouched (a closed team
    // slot just goes present:false); an unmatched window simply disappears.
    function close(selector) { if (selector) Hypr.close(selector); }

    // Present slots in team order — the roster the taskbar and cycling act on.
    function _present() { return (root.slots || []).filter(s => s.present); }

    // Per-window workspace, keyed by Hyprland address — because Quickshell
    // mis-maps XWayland toplevels' workspace (returns -1), so we ask hyprctl.
    // Drives both which workspace each chip is on (so the taskbar can limit
    // itself to the current one) and teamWorkspaceIds (where the team "is").
    property var wsByAddress: ({})
    // Workspace ids holding team windows, EXCLUDING special (negative) ones.
    property var teamWorkspaceIds: []
    Process {
        id: wsProbe
        command: ["bash", "-lc",
            "hyprctl clients -j | jq -c '[.[] | select(.class==\"Dofus.x64\") | {a: .address, w: .workspace.id}]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let rows = [];
                try { rows = JSON.parse((this.text || "[]").trim()); } catch (e) { rows = []; }
                const map = ({}), ws = ({});
                for (const r of rows) {
                    map[r.a] = r.w;
                    if (r.w >= 0) ws[r.w] = true;   // ignore special workspaces
                }
                root.wsByAddress = map;
                root.teamWorkspaceIds = Object.keys(ws).map(Number);
                root._rebuild();   // ws is an input to the join
            }
        }
    }
    Timer {
        interval: 1500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!wsProbe.running) wsProbe.running = true;
    }

    // Is the given workspace id one the team is on right now (special excluded)?
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
        root.focus(present[next].selector);
    }

    // Like cycle(), but once past the present team it continues into the
    // unmatched Dofus windows (ordered by focus recency), then wraps. So H/L
    // walk the whole roster, spilling over to stray windows at the ends.
    function _cycleOrder() {
        const extra = (root.unmatched || []).slice()
            .sort((a, b) => a.focusHistoryId - b.focusHistoryId);
        return root._present().concat(extra);
    }
    function cycleAll(reversed) {
        const list = root._cycleOrder();
        if (list.length === 0) return;
        const at = list.findIndex(s => s.focused);
        const n = list.length;
        const next = at < 0 ? 0 : (reversed ? (at - 1 + n) % n : (at + 1) % n);
        root.focus(list[next].selector);
    }

    // Focus+raise the team member at a 0-based team index (no-op if absent).
    function activate(index) {
        const s = (root.slots || [])[index];
        if (s && s.present) root.focus(s.selector);
    }

    // Focus+raise the 0-based Nth PRESENT (alive) team member, in team order.
    // Unlike activate(), this ignores absent slots — so with only 2 windows open,
    // indices 0 and 1 hit them regardless of their raw position in the team.
    function activatePresent(index) {
        const s = root._present()[index];
        if (s) root.focus(s.selector);
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
            const all = (root.slots || []).filter(s => s.present).concat(root.unmatched || []);
            const s = all.find(x => x.name === name);
            if (s) root.focus(s.selector);
        }
        // Turn-order navigation, offloaded from the Hyprland config.
        function next(): void { root.cycle(false); }
        function prev(): void { root.cycle(true); }
        // Same, but spilling into unmatched windows at the ends (for MOD+H/L).
        function nextAll(): void { root.cycleAll(false); }
        function prevAll(): void { root.cycleAll(true); }
        function activate(index: int): void { root.activate(index); }
        function activatePresent(index: int): void { root.activatePresent(index); }
    }
}
