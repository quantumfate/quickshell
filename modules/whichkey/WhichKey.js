// WhichKey.js — tree logic for the which-key overlay (LEO-222).
//
// The overlay's job is purely visual: Hyprland owns navigation (hypr/lib/
// submap.lua binds escape to one-level back and leaf actions to full exit),
// the Lua config owns the tree, and this file decides what to draw for the
// submap Hyprland is currently in. Kept as a `.pragma library` so the logic is
// testable from node (tests/qml.js wraps it) while the QML stays a thin
// renderer.
.pragma library

/**
 * The node currently on stage (from the submap event), or null.
 * `name` is "" at the root/unbound; "reset" is the base submap.
 */
function nodeFor(nodes, name) {
    if (!name || name === "reset") return null;
    return nodes[name] || null;
}

/**
 * Breadcrumb from the current submap up to the tree root, for the header.
 * A missing node degrades to just the submap's own name.
 */
function pathFromRoot(nodes, name) {
    const path = [];
    let cur = name || "";
    while (cur) {
        path.unshift(cur);
        const n = nodes[cur];
        if (!n) break;
        cur = n.parent || "";
    }
    return path;
}

/**
 * Render rows for a node. Each entry becomes a key combo (mods + key pill) and
 * a description; groups get flagged so the UI can show navigation affordance.
 * Undescribed rows are dropped — the cheatsheet's one hard rule.
 */
function rowsFor(node) {
    if (!node || !Array.isArray(node.items)) return [];
    const rows = [];
    for (const it of node.items) {
        const mods = Array.isArray(it.mods) ? it.mods : [];
        const combo = mods.concat([it.key]).join("+");
        if (!it.key || !it.desc) continue;
        rows.push({
            key: it.key,
            combo,
            desc: it.desc,
            group: !!it.group,
            child: it.child || "",
        });
    }
    return rows;
}