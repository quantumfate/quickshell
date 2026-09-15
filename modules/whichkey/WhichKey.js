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
        const combo = mods.concat([it.key]).map(
            p => keyGlyph(String(p || "").toLowerCase())).join("+");
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

/**
 * The entrance/exit fade the mode's motion contract names (LEO-227): an
 * `instant` mode gets what is effectively an instant swap — the overlay
 * tracks the submap stack at keyboard speed. A `base` mode gets the gentle
 * fade. THE LINGERING TAIL IS NOT THIS NUMBER: the exit fade animates
 * opacity while the surface is already logically gone (unmapped on close()),
 * so no exit fade can hold input a keystroke meant for the base map.
 *
 * @param motionEnergy "base"|"instant" — Focus.motionEnergy
 * @param instantMs millisecond value an instant mode's contract means (30)
 * @param baseMs the felt-which-key dwell (90)
 */
function fadeFor(motionEnergy, instantMs, baseMs) {
    return motionEnergy === "instant" ? (instantMs || 30) : (baseMs || 90);
}

/**
 * The tail of a dismissal: ZERO by contract. The close path unmaps the
 * surface in the same tick the key leaves the submap — there is no linger
 * timer to mis-order with the submap reset, and no number the mode can
 * stretch. Kept as a named constant so the model answers the question.
 */
function snapAfterLeave() {
    return 0;
}

/**
 * The human-readable key label (LEO-306): the same table the cheat sheet's
 * model uses (a ".pragma library" cannot import another), so both surfaces
 * spell a chord the same way. A glyph table for xkb words plus the named
 * special keys; everything else passes through unmolested.
 */
var KEY_GLYPHS = {
    ampersand: "&", apostrophe: "'", asterisk: "*", at: "@", backslash: "\\",
    braceleft: "{", braceright: "}", comma: ",", degree: "°", dollar: "$",
    equal: "=", exclam: "!", grave: "`", greater: ">", less: "<", minus: "-",
    numbersign: "#", parenleft: "(", parenright: ")", percent: "%",
    period: ".", plus: "+", plusminus: "±", question: "?", quotedbl: "\"",
    semicolon: ";", slash: "/", underscore: "_", division: "÷",
    multiply: "×", euro: "€", sterling: "£", asciitilde: "~",
    asciicircum: "^", section: "§", mu: "µ",
};
var NAMED_KEYS = {
    space: "Space", escape: "Esc", return_: "Return", Return: "Return",
    Tab: "Tab", BackSpace: "Backspace", prior: "PgUp", next: "PgDn",
    Delete: "Del", Insert: "Ins", Home: "Home", End: "End"
};

function keyGlyph(key) {
    if (key === undefined || key === null) return "";
    if (Object.prototype.hasOwnProperty.call(KEY_GLYPHS, key)) return KEY_GLYPHS[key];
    if (Object.prototype.hasOwnProperty.call(NAMED_KEYS, key)) return NAMED_KEYS[key];
    return key;
}

