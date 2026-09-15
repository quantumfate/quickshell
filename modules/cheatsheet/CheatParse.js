// Shared cheatsheet rendering. Stateless: turns a which-key registry node —
// the same document the overlay and the full panel both read — into balanced,
// categorized columns. Used by the full CheatSheet overlay (SUPER+/) so the
// reference view agrees with the live which-key overlay on grouping.
//
// The data plane is the dump (LEO-268): the Lua registry records every
// described bind at load, and each mode's converge narrows it to the trees
// its declaration admits — so what both panels render IS the enabled set.
// The old `hyprctl binds` parse and the context filter it needed (LEO-223)
// are replaced by admission: a row that would do nothing is not in the dump.
.pragma library

/**
 * A registry item's literal combo: mods in the order the tree recorded them,
 * key last — already the words the key pill reads.
 */
function combo(mods, key) {
    var parts = mods ? mods.slice() : [];
    parts.push(key);
    return parts.join(" + ");
}

// Derive a category + tidy label from a bind description. A "Cat: label" prefix
// wins (e.g. "Workspace: Focus 5"); otherwise bucket by keywords. Undescribed
// rows are dropped by the parse — the one hard rule.
function categorize(desc) {
    var m = desc.match(/^([A-Za-z][\w &/'-]*?):\s*(.+)$/);
    if (m) return { cat: m[1], label: m[2] };
    if (desc.endsWith("…") || desc.endsWith("...")) return { cat: "Menus", label: desc };
    var d = desc.toLowerCase();
    if (/volume|mute|media|player|track|brightness/.test(d)) return { cat: "Media", label: desc };
    // Workspace before window: "focus workspace 5" matches both, and it is a
    // workspace bind. Most real binds carry a "Workspace:" prefix and never
    // reach here, which is why the precedence went unnoticed.
    if (/workspace/.test(d)) return { cat: "Workspace", label: desc };
    if (/window|focus|swap|close|minimize|float|fullscreen|maximize/.test(d)) return { cat: "Window", label: desc };
    if (/keyboard layout|screen|capture|hyprpicker|hex|picker/.test(d)) return { cat: "Utilities", label: desc };
    return { cat: "General", label: desc };
}


/**
 * Parse a registry node (the shape `hypr/lib/whichkey.lua` dumps: the tree's
 * items carry key, mods, desc) into ordered categories, where each row's combo
 * reads in human glyphs (LEO-306): the chord the desk speaks in xkb words
 * ("ampersand", "braceleft", "slash") renders as what the keyboard shows.
 */
function parseNode(node, categoryOrder) {
    var items = node && Array.isArray(node.items) ? node.items : [];
    var seen = {};
    var groups = {};
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        if (!item || !item.desc) continue;
        var parts = categorize(item.desc);
        var combo = (item.mods || [])
            .concat([item.key]).map(function (part) {
                return keyGlyph(String(part || "").toLowerCase());
            }).join(" + ");
        var dedup = parts.cat + "|" + combo + "|" + parts.label;
        if (seen[dedup]) continue;
        seen[dedup] = true;
        (groups[parts.cat] || (groups[parts.cat] = [])).push({ combo: combo, desc: parts.label });
    }
    var rank = function (n) { var i = categoryOrder.indexOf(n); return i === -1 ? categoryOrder.length : i; };
    return Object.keys(groups)
        .sort(function (a, b) { return (rank(a) - rank(b)) || a.localeCompare(b); })
        .map(function (name) {
            return {
                name: name,
                rows: groups[name].sort(function (x, y) { return x.combo.localeCompare(y.combo); })
            };
        });
}

/**
 * The node the sheet's current context shows: the entered submap's registry
 * node, or the root's at rest. A submap no longer registered (withheld, or a
 * stale name) degrades to the root — the sheet cannot show a context it has
 * no truth for.
 */
function nodeAs(nodes, submap) {
    var t = nodes || {};
    if (!submap || submap === "reset") return t["reset"] || { parent: "", items: [] };
    return t[submap] || t["reset"] || { parent: "", items: [] };
}

function splitColumns(cats) {
    var sorted = cats.slice().sort(function (a, b) { return a.name.localeCompare(b.name); });
    var half = Math.ceil(sorted.length / 2);
    return [sorted.slice(0, half), sorted.slice(half)];
}

// Human-readable key labels (LEO-306): a chord the desk speaks in xkb words
// ("ampersand", "braceleft") renders as the glyph the keyboard shows, so the
// sheet reads at a glance instead of sending the reader to a key-symbol
// table. Xf86/scrollwheel keys carry no glyph and keep their names.
var KEY_GLYPHS = {
    ampersand: "&", apostrophe: "'", asterisk: "*", at: "@", backslash: "\\",
    braceleft: "{", braceright: "}", comma: ",",
    degree: "°", dollar: "$", equal: "=", exclam: "!", grave: "`",
    greater: ">", less: "<", minus: "-", numbersign: "#", parenleft: "(",
    parenright: ")", percent: "%", period: ".", plus: "+", plusminus: "±",
    question: "?", quotedbl: "\"", semicolon: ";", slash: "/",
    underscore: "_", division: "÷", multiply: "×", euro: "€",
    sterlingicon: "£", sterling: "£", asciitilde: "~", asciicircum: "^",
    section: "§", mu: "µ", eta: "η",
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
