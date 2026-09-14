.pragma library
// Pure logic for the workspace switcher overlay (WorkspaceSwitcher.qml).
// Kept separate from the QML so it can be unit-tested against plain fixtures
// rather than live Hyprland/Quickshell objects — see tests/workspaceswitch.test.js.

// Per-workspace icon by name, mirroring Workspaces.qml's own map. Duplicated
// rather than shared: Workspaces.qml's version lives in a QML property object,
// which this plain-JS library cannot import.
const ICON_BY_NAME = {
    "code": "",
    "creative": "",
    "proton": "",
    "media": "",
    "gaming": "",
    "logs": "",
    "misc": ""
};

// The canonical order of the named workspaces — the order the config's
// workspace_keys spell (Workspaces.qml mirrors it). Named workspaces the host
// never declared follow numeric ones, id-ascending.
const ORDER = ["code", "creative", "proton", "media", "gaming", "logs", "misc"];

// The config talks about named workspaces by name (binds, window rules, the
// scene actuator); the compositor may hold BOTH an id-backed twin (the
// persistent rule's creation, id > 0) and a named one (`name:…` dispatch,
// id < 0). They are one slot: the named twin is the one those flows occupy,
// so merging by name keeps a single pill per declared workspace.
//
// workspaces: [{ id, name }] — real, non-special workspaces.
// -> one workspace per declared name (named twin preferred), then undeclared
//    ones by id. Sort = declared order, undeclared ids after.
function canonical(workspaces) {
    const byName = new Map();
    const rest = [];
    for (const w of (workspaces || [])) {
        if (!ORDER.includes(w.name)) {
            rest.push(w);
            continue;
        }
        const kept = byName.get(w.name);
        if (!kept || (kept.id > 0 && w.id < 0)) byName.set(w.name, w);
    }
    const named = [...byName.values()]
        .sort((a, b) => ORDER.indexOf(a.name) - ORDER.indexOf(b.name));
    rest.sort((a, b) => a.id - b.id);
    return named.concat(rest);
}

// The selector a dispatch speaks for a workspace row: named workspaces by
// name (their auto id is an internal handle), numeric ones by id.
function selector(w) {
    return w.name ? "name:" + w.name : String(w.id);
}

function iconFor(name, id) {
    return ICON_BY_NAME[name] ?? ((id > 0 && id < 10) ? String(id) : "");
}

// workspaces: [{ id, name }]  (canonical, from canonical())
// windows:    [{ wsId, title }]
// -> [{ id, name, icon, windows: [title, ...] }], in canonical order.
function buildRows(workspaces, windows) {
    const byWs = new Map();
    for (const w of (windows || [])) {
        if (w.wsId === undefined) continue;
        if (!byWs.has(w.wsId)) byWs.set(w.wsId, []);
        byWs.get(w.wsId).push(w.title);
    }
    return canonical(workspaces).map(ws => ({
            id: ws.id,
            name: ws.name,
            icon: iconFor(ws.name, ws.id),
            windows: byWs.get(ws.id) || []
        }));
}

// Case-insensitive filter over workspace id, name, and window titles. Empty
// query returns every row unchanged.
function filterRows(rows, query) {
    const q = (query || "").trim().toLowerCase();
    if (!q) return rows;
    return rows.filter(r =>
        String(r.id).includes(q)
        || (r.name || "").toLowerCase().includes(q)
        || (r.windows || []).some(t => (t || "").toLowerCase().includes(q))
    );
}
