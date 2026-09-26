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
    if (id > 0 && id < 10) return String(id);
    // A declared scene with no glyph still has to be SEEN: it is a row of the
    // mode, clickable, and the keyboard reaches it. `logs` lost its icon in a
    // declaration rewrite and its row then drew zero pixels wide -- present in
    // the model, invisible on the bar, which reads as the scene not being
    // there at all (live, 2026-09-25). Its own initial stands in.
    if (name) return name.charAt(0).toUpperCase();
    return "";
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
 * The bar pill's rows for one monitor: EVERY scene the active mode admits
 * for `role`, in declared order — including one Hyprland has not created a
 * workspace for yet, as a synthetic zero-window row (`id: null`) — plus any
 * other real workspace that still holds windows, appended after, unordered
 * by name (hyprfocus hold semantics: a workspace a mode no longer admits
 * keeps its windows parked, not deleted). LEO-373: showing every admitted
 * scene up front, dormant or not, is the "clear choice on entry" the bar
 * gives a mode.
 *
 * workspaces: [{ id, name, occupied }]
 */
function barWorkspaces(declaration, modeId, role, workspaces) {
    const order = modeOrder(declaration, modeId, role);
    const inOrder = new Set(order);
    const byName = new Map((workspaces || []).map(w => [w.name, w]));
    const admitted = order.map(name => byName.get(name) || { id: null, name, occupied: false });
    const others = (workspaces || []).filter(w => !inOrder.has(w.name) && w.occupied);
    return orderBy(order, admitted.concat(others));
}

/**
 * A bar row's play state (LEO-373). `focused` wins outright; otherwise a row
 * with at least one window is `playing`, and a row with none — including a
 * synthetic row for a scene Hyprland has not created yet — is `dormant`.
 * Dormant is a display state only: the workspace is still admitted and its
 * positional key still works (mode admission is a separate concern, see
 * barWorkspaces()'s header).
 *
 * row: { occupied, active }
 */
function rowState(row) {
    if (row && row.active) return "focused";
    return (row && row.occupied) ? "playing" : "dormant";
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
 * Two calling conventions:
 * - `activeName(rows)` — legacy: trust each row's own `active` flag. Kept for
 *   callers that already resolved focus correctly by other means.
 * - `activeName(rows, activeWsName)` — LEO-371/LEO-337 follow-up: match by
 *   NAME against the monitor's own `activeWorkspace.name` instead. A
 *   workspace's per-object `active`/`focused` flag is driven by Quickshell's
 *   internal (id-keyed) tracking, which this Hyprland build starves of a
 *   real numeric id (every named workspace reports `id: -1` — see
 *   attachLive()'s header); that flag was observed to update only on a
 *   monitor-crossing focus change, not a plain same-monitor workspace
 *   switch. `HyprlandMonitor.activeWorkspace.name`, by contrast, is exactly
 *   what `hyprctl -j monitors` reports and updates on every switch.
 *
 * rows: [{ name, active }] — a monitor's ordered rows.
 * activeWsName: the focused monitor's `activeWorkspace.name`, when known.
 * -> the focused row's name, or "" when nothing on this monitor is focused
 *    yet, or the active workspace is not one of this monitor's admitted rows.
 */
function activeName(rows, activeWsName) {
    if (activeWsName !== undefined) {
        const w = (rows || []).find(r => r && r.name === activeWsName);
        return (w && w.name) || "";
    }
    const w = (rows || []).find(r => r && r.active);
    return (w && w.name) || "";
}

// Only names `,desk.sh` itself accepts (`^[A-Za-z0-9._-]+$`) — anything else
// is refused before it ever reaches a shell command.
const _SAFE_NAME = /^[A-Za-z0-9._-]+$/;

/**
 * The argv for a monitor-scoped workspace switch (LEO cross-repo "one seat"):
 * `,desk.sh switch <screenName> <row.name>`. The dot's TapHandler runs this
 * on the dot's OWN screen, never the seat — a click only ever changes the
 * monitor it was clicked on (`WorkspaceSwitcher.qml`'s `go()` is the seat's
 * version of the same seam, see `sendCommand`).
 *
 * A synthesized row (no live workspace yet, or a numeric-only name that does
 * not match `,desk.sh`'s own name pattern) returns null rather than a
 * half-built command — nothing here guesses a fallback name.
 */
function switchCommand(screenName, row) {
    const name = row && row.name;
    if (!screenName || !name || !_SAFE_NAME.test(name)) return null;
    return [",desk.sh", "switch", screenName, name];
}

/**
 * The argv for a seat-scoped workspace switch or send, from the switcher
 * overlay: `,desk.sh switch <seatMonitor> <row.name>`, or `send` instead of
 * `switch` when bringing the focused window along. The overlay always acts on
 * the SEAT (it opens over the keyboard's monitor), so unlike `switchCommand`
 * this takes the seat's monitor rather than a bar instance's own screen.
 */
function sendCommand(seatMonitor, row, bringWindow) {
    const name = row && row.name;
    if (!seatMonitor || !name || !_SAFE_NAME.test(name)) return null;
    return [",desk.sh", bringWindow ? "send" : "switch", seatMonitor, name];
}

/**
 * Which monitor role (`"primary"`/`"secondary"`) a screen plays, from the
 * `geometry` store's `roles` map (LEO-368): `{ primary: "<output>", secondary:
 * "<output>" }`, published by hypr's conf/host.lua next to the per-output
 * gaps (see services/BarGaps.js) from the host's own `primary_monitor`/
 * `secondary_monitor` and which outputs are actually connected — an
 * unconnected or ignored output is omitted from the map entirely, never
 * defaulted onto another role.
 *
 * An empty or missing map (an older store published before LEO-368) reads
 * every screen as primary, so a single-monitor host still bars correctly
 * while the store catches up. Once a map exists, a screen it does not name
 * as `primary` reads as secondary: it is safer to under-place an
 * unrecognised or disconnected output than to duplicate the primary role
 * onto it.
 */
function roleForScreen(roles, screenName) {
    if (!roles || Object.keys(roles).length === 0) return "primary";
    return screenName === roles.primary ? "primary" : "secondary";
}

/**
 * Attach each bar row's live Hyprland object back onto barWorkspaces()'s
 * result. Rows are matched by NAME, never by `id`: a named workspace's id is
 * not a trustworthy per-workspace handle (some Hyprland builds report the
 * same id — e.g. -1 — for every named workspace, since they carry no
 * numeric identity at all), so keying a live-object map by id can collapse
 * several distinct named workspaces onto one map entry, silently duplicating
 * whichever workspace inserted last across every other row that resolved to
 * a real match (LEO-344).
 *
 * A SYNTHESIZED row (`id: null`) takes its live object too, when one exists.
 * It used to pass through untouched, and that was the bug the dot row made
 * visible: the rows come from the declaration, and a row is only born with an
 * id when the monitor-filtered list contained it — which needs
 * `workspace.monitor.name`, unresolved on this build for nearly every
 * workspace (see Workspaces.qml's `_sorted`). So every row stayed
 * synthesized, and with it every row read as having no windows and never
 * being the active one: four dim dots on a screen whose scene was standing
 * right there with five windows in it. Synthesized means "not created yet",
 * and a name that matches a live workspace is exactly the proof that it was.
 *
 * rows: barWorkspaces()'s result — one entry per bar row, `id: null` marking
 *       a synthesized (not-yet-created) row.
 * live: the real Hyprland workspace objects rows may match by name.
 * -> rows, each replaced by its live object where one exists by name.
 */
function attachLive(rows, live) {
    const byName = new Map((live || []).map(w => [w.name, w]));
    return (rows || []).map(w => byName.get(w.name) ?? w);
}
