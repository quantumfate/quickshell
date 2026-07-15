pragma Singleton
// Dofus team state — a thin, domain-specific view over a generic Store.
// The Store handles the file<->RAM<->reactive bridge (see Store.qml); this adds
// the ordered-team semantics the UI and Hyprland config care about.
//
// List ORDER is meaningful: turn order, F1..F8, launch order, swap args.
import Quickshell
import Quickshell.Io
import QtQuick
import "."

Singleton {
    id: root

    Store { id: store; name: "dofus/team" }

    readonly property string titlePrefix: store.get("title_prefix") ?? "Dofus "
    readonly property string selected: store.get("selected") ?? "pioneer"
    readonly property var teams: store.data.teams ?? ({})
    readonly property var team: teams[selected] ?? []

    // ---- mutators (all keep order, all persist through the Store) ----------

    function selectTeam(key) {
        if (teams[key]) store.set({ selected: key });
    }

    function reorder(from, to) {
        const t = (team || []).slice();
        if (from < 0 || from >= t.length || to < 0 || to >= t.length) return;
        t.splice(to, 0, t.splice(from, 1)[0]);
        _setTeam(t);
    }

    function rename(index, name) {
        const t = (team || []).slice();
        if (index >= 0 && index < t.length) { t[index] = name; _setTeam(t); }
    }

    function add(name) {
        const t = (team || []).slice();
        t.push(name);
        _setTeam(t);
    }

    function remove(index) {
        const t = (team || []).slice();
        if (index >= 0 && index < t.length) { t.splice(index, 1); _setTeam(t); }
    }

    function _setTeam(list) {
        const teamsCopy = Object.assign({}, teams);
        teamsCopy[selected] = list;
        store.set({ teams: teamsCopy });
    }

    // ---- scripting surface: qs -c quantumfate ipc call dofus <fn> ----------
    IpcHandler {
        target: "dofus"
        function team(): string { return (root.team || []).join("\n"); }
        function selected(): string { return root.selected; }
        function select(key: string): void { root.selectTeam(key); }
        function reload(): void { store.reload(); }
    }
}
