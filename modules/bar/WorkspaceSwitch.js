.pragma library
// Pure logic for the workspace switcher overlay (WorkspaceSwitcher.qml) and
// the per-monitor workspace pill (Workspaces.qml). Kept separate from the
// QML so it can be unit-tested against plain fixtures rather than live
// Hyprland/Quickshell objects — see tests/workspaceswitch.test.js.
//
// LEO-343: order and icons come from the hyprfocus declaration, never a
// hardcoded name list. `declaration` throughout is the raw store document
// (`{ base: { scenes }, modes }`, the shape services/Hyprfocus.qml exposes as
// `Hyprfocus.data`) — these functions only read it, never resolve one (that
// stays hypr's/the CLI's job, see services/HyprfocusRead.js's header).

/** Scene names in `base.scenes` declaration order — the catalog order. */
function catalogOrder(declaration) {
    const scenes = (declaration && declaration.base && declaration.base.scenes) || {};
    return Object.keys(scenes);
}

/**
 * The active mode's admitted scene names for one monitor role, in the
 * mode's declared order.
 */
function modeOrder(declaration, modeId, role) {
    const mode = ((declaration && declaration.modes) || {})[modeId];
    const scenes = (mode && mode.scenes) || [];
    return scenes.filter(s => s.monitor === role).map(s => s.name);
}

/**
 * A scene's icon glyph, or a numeric/dot fallback for an undeclared
 * workspace (`id` 1-9 shows as a digit, everything else a plain dot).
 */
function iconFor(declaration, name, id) {
    const scenes = (declaration && declaration.base && declaration.base.scenes) || {};
    const scene = scenes[name];
    if (scene && scene.icon) return scene.icon;
    return (id > 0 && id < 10) ? String(id) : "";
}

// The config talks about named workspaces by name (binds, window rules, the
// scene actuator); the compositor may hold BOTH an id-backed twin (the
// persistent rule's creation, id > 0) and a named one (`name:…` dispatch,
// id < 0). They are one slot: the named twin is the one those flows occupy,
// so merging by name keeps a single pill per declared workspace.
//
// order: [name, ...] — declared order for the names this call sorts by.
// workspaces: [{ id, name }] — real, non-special workspaces.
// -> one workspace per name in `order` (named twin preferred), then every
//    other workspace by id. Sort = `order`, then undeclared ids after.
function orderBy(order, workspaces) {
    const inOrder = new Set(order);
    const byName = new Map();
    const rest = [];
    for (const w of (workspaces || [])) {
        if (!inOrder.has(w.name)) {
            rest.push(w);
            continue;
        }
        const kept = byName.get(w.name);
        if (!kept || (kept.id > 0 && w.id < 0)) byName.set(w.name, w);
    }
    const named = [...byName.values()]
        .sort((a, b) => order.indexOf(a.name) - order.indexOf(b.name));
    rest.sort((a, b) => a.id - b.id);
    return named.concat(rest);
}

/**
 * Full-catalog order for the switcher overlay: every real workspace is
 * shown (that surface's job is "jump to any workspace by search"), sorted by
 * the declaration's scene catalog, undeclared ones after by id.
 *
 * workspaces: [{ id, name }]
 */
function canonical(declaration, workspaces) {
    return orderBy(catalogOrder(declaration), workspaces);
}

/**
 * The bar pill's rows for one monitor: the active mode's admitted scenes for
 * `role`, in declared order, plus any other real workspace that still holds
 * windows — appended after, unordered by name (hyprfocus hold semantics: a
 * workspace a mode no longer admits keeps its windows parked, not deleted).
 *
 * workspaces: [{ id, name, occupied }]
 */
function barWorkspaces(declaration, modeId, role, workspaces) {
    const order = modeOrder(declaration, modeId, role);
    const inOrder = new Set(order);
    const admitted = (workspaces || []).filter(w => inOrder.has(w.name));
    const others = (workspaces || []).filter(w => !inOrder.has(w.name) && w.occupied);
    return orderBy(order, admitted.concat(others));
}

// The selector a dispatch speaks for a workspace row: named workspaces by
// name (their auto id is an internal handle), numeric ones by id.
function selector(w) {
    return w.name ? "name:" + w.name : String(w.id);
}

// workspaces: [{ id, name }], already in the desired order (canonical() or
// barWorkspaces()).
// windows:    [{ wsId, title }]
// -> [{ id, name, icon, windows: [title, ...] }], in the given order.
function buildRows(declaration, workspaces, windows) {
    const byWs = new Map();
    for (const w of (windows || [])) {
        if (w.wsId === undefined) continue;
        if (!byWs.has(w.wsId)) byWs.set(w.wsId, []);
        byWs.get(w.wsId).push(w.title);
    }
    return (workspaces || []).map(ws => ({
            id: ws.id,
            name: ws.name,
            icon: iconFor(declaration, ws.name, ws.id),
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

/**
 * The active row's scene name for one monitor's bar (LEO-371): workspaces are
 * named by scene already, so the focused row's `name` IS the scene name —
 * this just picks it out rather than making a bar delegate re-derive it.
 *
 * rows: [{ name, active }] — a monitor's ordered rows (barWorkspaces() +
 * Hyprland's per-workspace `active` flag merged in by the caller).
 * -> the focused row's name, or "" when nothing on this monitor is focused
 *    (a fresh monitor before Hyprland reports focus, e.g.).
 */
function activeName(rows) {
    const w = (rows || []).find(r => r.active);
    return (w && w.name) || "";
}

/**
 * Which monitor role (`"primary"`/`"secondary"`) a screen plays, from the
 * `geometry` store's `monitors` map (keyed by real output name, published by
 * hypr's conf/host.lua — see services/BarGaps.js).
 *
 * Every host file's workspace_specs lists its primary-role workspace first
 * (the default/unset-monitor case) and any secondary-role one later,
 * explicitly marked (`monitor = "secondary"`) — see conf/hosts/*.lua in the
 * hypr repo. `geometry.monitor_gaps()` (hypr/lib/geometry.lua) builds the
 * published map by walking that same spec order and keeping the first gap
 * seen per output, so its key order mirrors the spec order: the primary
 * output is always the map's first key. This is the one role signal the
 * shell has without re-reading hypr's host files — no `primary`/`secondary`
 * mapping is otherwise published to a store the shell can read.
 *
 * A screen absent from the map (an older store, or a monitor the store has
 * not been rewritten for yet) reads as secondary: it is safer to under-place
 * an unrecognised output than to duplicate the primary role onto it.
 */
function roleForScreen(monitors, screenName) {
    const names = Object.keys(monitors || {});
    if (names.length === 0) return "primary";
    return screenName === names[0] ? "primary" : "secondary";
}
