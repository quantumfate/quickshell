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
    return motionEnergy === "instant" ? 0 : (baseMs || 90);
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
 * Session state: { submap, shown, dwellArmed }. `submap` is the last raw
 * event's data ("" or "reset" at root); `shown` is whether the overlay is
 * mapped; `dwellArmed` is whether a dwell timer is pending before it opens.
 * The initial session, before any submap event has landed.
 */
function initialSession() {
    return { submap: "", shown: false, dwellArmed: false };
}

/**
 * The overlay's timing/decision logic (LEO-300), as a pure reducer: given the
 * current session and one event, the next session. QML drives a Timer and an
 * IpcHandler off this so the state machine itself — not just its numbers — is
 * unit-testable from node, independent of a running compositor.
 *
 * Events:
 *   { type: "submap", data }  — a Hyprland `submap` raw event landed.
 *   { type: "dismiss" }       — the `whichkey dismiss`/`hide` IPC landed.
 *   { type: "dwellFired" }    — the armed dwell timer elapsed.
 *
 * Leaving to root ("" or "reset") or an explicit dismiss both close with NO
 * dwell — the dwell only ever gates the overlay *appearing*, never leaving.
 * Moving between non-root submaps while already shown never re-arms the
 * dwell — it stays open and just follows. `dwellFired` re-checks `submap`
 * before opening, so a dwell that was left running past a leave (defensive:
 * QML also stops the Timer synchronously on every leave/dismiss) can never
 * paint a node the user already left.
 *
 * @param {{submap: string, shown: boolean, dwellArmed: boolean}} session
 * @param {{type: string, data?: string}} event
 * @returns {{submap: string, shown: boolean, dwellArmed: boolean}}
 */
function reduceSession(session, event) {
    if (event.type === "submap") {
        const submap = event.data || "";
        const inSubmap = submap !== "" && submap !== "reset";
        if (!inSubmap) {
            // Back at root: dismiss immediately, whether or not a dwell for
            // the submap just left was still pending.
            return { submap, shown: false, dwellArmed: false };
        }
        if (session.shown) {
            // Already open: follow to the new submap, no re-arm.
            return { submap, shown: true, dwellArmed: false };
        }
        // Not yet open: arm the dwell for this entry.
        return { submap, shown: false, dwellArmed: true };
    }
    if (event.type === "dismiss") {
        // Explicit dismiss wins immediately, regardless of a pending dwell.
        return { submap: session.submap, shown: false, dwellArmed: false };
    }
    if (event.type === "dwellFired") {
        const inSubmap = session.submap !== "" && session.submap !== "reset";
        if (!inSubmap) {
            // Raced a leave that didn't stop the timer: never open on a node
            // already left.
            return Object.assign({}, session, { dwellArmed: false });
        }
        return Object.assign({}, session, { shown: true, dwellArmed: false });
    }
    return session;
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

