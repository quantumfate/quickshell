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

    Store {
        id: store
        name: "dofus/team"
        // Seed on first run (fresh machine/checkout) so the team exists without
        // manual provisioning. Order is meaningful.
        defaults: ({
            title_prefix: "Dofus ",
            selected: "pioneer",
            pool: [
                "Reminiscer", "Sayer", "Rejecter", "Draintouch",
                "Traumafactory", "Memoryfracture", "Dissipate", "Miserymaker",
                "Flamewarden", "Tideseeker", "Stormcaller", "Earthsong",
                "Crusher", "Healer", "Buffer", "Debuffer", "Nuker",
                "Iop", "Eniripsa", "Cra", "Sadida", "Enutrof", "Sram"
            ],
            teams: {
                pioneer: [
                    "Reminiscer", "Sayer", "Rejecter", "Draintouch",
                    "Traumafactory", "Memoryfracture", "Dissipate", "Miserymaker"
                ],
                elemental: [
                    "Flamewarden", "Tideseeker", "Stormcaller", "Earthsong"
                ],
                pvm: [
                    "Crusher", "Healer", "Buffer", "Debuffer", "Nuker"
                ],
                krosmoz: [
                    "Iop", "Eniripsa", "Cra", "Sadida", "Enutrof", "Sram"
                ]
            }
        })
    }

    readonly property string titlePrefix: store.get("title_prefix") ?? "Dofus "
    readonly property string selected: store.get("selected") ?? "pioneer"
    readonly property var pool: store.data.pool ?? ([])
    readonly property var teams: store.data.teams ?? ({})
    readonly property var team: teams[selected] ?? []
    // Character name -> class key (see DofusClasses). A side map keyed by name,
    // because names are the identity used everywhere (pool/teams); absent = "".
    readonly property var classes: store.data.classes ?? ({})

    // The class key for a character, or "" when unset/unknown.
    function classOf(name) { return root.classes[name] ?? ""; }

    // Set (or clear, when cls is "") a character's class; persists through Store.
    function setClass(name, cls) {
        const n = (name || "").trim();
        if (!n) return;
        const copy = Object.assign({}, root.classes);
        if (cls) copy[n] = cls; else delete copy[n];
        store.set({ classes: copy });
    }

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

    // Add to the selected team; also folds the name into the pool (pool is the
    // set of all known characters, so team ⊆ pool always holds).
    function add(name) {
        const n = (name || "").trim();
        if (!n) return;
        const t = (team || []).slice();
        if (t.indexOf(n) >= 0) return;   // one character per team — no duplicates
        t.push(n);
        const teamsCopy = Object.assign({}, teams);
        teamsCopy[selected] = t;
        const patch = { teams: teamsCopy };
        if (pool.indexOf(n) < 0) patch.pool = pool.concat([n]);
        store.set(patch);
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

    // ---- pool mutators ------------------------------------------------------

    function addToPool(name) {
        const n = (name || "").trim();
        if (!n || pool.indexOf(n) >= 0) return;
        store.set({ pool: pool.concat([n]) });
    }

    // Remove from the pool AND cascade: drop the name from every team roster,
    // since a team member must exist in the pool.
    function removeFromPool(name) {
        const idx = pool.indexOf(name);
        if (idx < 0) return;
        const p = pool.slice();
        p.splice(idx, 1);
        const copy = {};
        for (const k of Object.keys(teams)) copy[k] = (teams[k] || []).filter(x => x !== name);
        // Drop the orphaned class entry too — no character left to own it.
        const cls = Object.assign({}, root.classes);
        delete cls[name];
        store.set({ pool: p, teams: copy, classes: cls });
    }

    // Rename a character everywhere in state: the pool and every team roster
    // (order preserved). Blocked if the new name is empty or already taken in
    // the pool. Live windows are retitled separately (see DofusWindows).
    function renameCharacter(oldName, newName) {
        const n = (newName || "").trim();
        if (!n || n === oldName) return;
        if (pool.indexOf(n) >= 0) return; // one character per pool — no clash
        const p = pool.map(x => x === oldName ? n : x);
        const copy = {};
        for (const k of Object.keys(teams)) {
            copy[k] = (teams[k] || []).map(x => x === oldName ? n : x);
        }
        // Carry the class over to the new name (identity moves with the rename).
        const cls = Object.assign({}, root.classes);
        if (cls[oldName] !== undefined) { cls[n] = cls[oldName]; delete cls[oldName]; }
        store.set({ pool: p, teams: copy, classes: cls });
    }

    // ---- team CRUD ----------------------------------------------------------

    function renameTeam(oldKey, newKey) {
        const k = (newKey || "").trim();
        if (!k || k === oldKey || !teams[oldKey] || teams[k]) return;
        const copy = {};
        // Rebuild to preserve pill order (Object key insertion order).
        for (const key of Object.keys(teams)) copy[key === oldKey ? k : key] = teams[key];
        const patch = { teams: copy };
        if (selected === oldKey) patch.selected = k;
        store.set(patch);
    }

    function createTeam(key) {
        const k = (key || "").trim();
        if (!k || teams[k]) return;
        const copy = Object.assign({}, teams);
        copy[k] = [];
        store.set({ teams: copy });
    }

    function deleteTeam(key) {
        if (!teams[key]) return;
        const copy = Object.assign({}, teams);
        delete copy[key];
        const patch = { teams: copy };
        if (selected === key) patch.selected = Object.keys(copy)[0] ?? "";
        store.set(patch);
    }

    // ---- scripting surface: qs -c quantumfate ipc call dofus <fn> ----------
    IpcHandler {
        target: "dofus"
        function team(): string { return (root.team || []).join("\n"); }
        function pool(): string { return (root.pool || []).join("\n"); }
        function selected(): string { return root.selected; }
        function select(key: string): void { root.selectTeam(key); }
        function addToPool(name: string): void { root.addToPool(name); }
        function removeFromPool(name: string): void { root.removeFromPool(name); }
        function createTeam(key: string): void { root.createTeam(key); }
        function renameTeam(oldKey: string, newKey: string): void { root.renameTeam(oldKey, newKey); }
        function deleteTeam(key: string): void { root.deleteTeam(key); }
        function renameCharacter(oldName: string, newName: string): void { root.renameCharacter(oldName, newName); }
        function classOf(name: string): string { return root.classOf(name); }
        function setClass(name: string, cls: string): void { root.setClass(name, cls); }
        function reload(): void { store.reload(); }
    }
}
