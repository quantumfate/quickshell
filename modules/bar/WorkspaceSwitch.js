.pragma library
// Pure logic for the workspace switcher overlay (WorkspaceSwitcher.qml).
// Kept separate from the QML so it can be unit-tested against plain fixtures
// rather than live Hyprland/Quickshell objects — see tests/workspaceswitch.test.js.

// Per-workspace icon by name, mirroring Workspaces.qml's own map. Duplicated
// rather than shared: Workspaces.qml's version lives in a QML property object,
// which this plain-JS library cannot import.
const ICON_BY_NAME = {
    "code": "",
    "creative": "",
    "proton": "",
    "media": "",
    "gaming": "",
    "logs": "",
    "misc": ""
};

function iconFor(name, id) {
    return ICON_BY_NAME[name] ?? ((id > 0 && id < 10) ? String(id) : "");
}

// workspaces: [{ id, name }]  (real, non-special workspaces)
// windows:    [{ wsId, title }]
// -> [{ id, name, icon, windows: [title, ...] }], sorted by id.
function buildRows(workspaces, windows) {
    const byWs = new Map();
    for (const w of (windows || [])) {
        if (!byWs.has(w.wsId)) byWs.set(w.wsId, []);
        byWs.get(w.wsId).push(w.title);
    }
    return (workspaces || [])
        .slice()
        .sort((a, b) => a.id - b.id)
        .map(ws => ({
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
