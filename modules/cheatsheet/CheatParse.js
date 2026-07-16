// Shared cheatsheet bind parsing. Stateless: turns `hyprctl binds -j` output
// into balanced, categorized columns. Used by both the full CheatSheet overlay
// and the passive CheatSheetPeek panel so they always agree on grouping.
.pragma library

// Hyprland modmask bit flags -> readable names.
var MOD_NAMES = { 1: "SHIFT", 4: "CTRL", 8: "ALT", 64: "SUPER" };

function combo(modmask, key) {
    var parts = [];
    for (var bit in MOD_NAMES)
        if ((modmask & bit) === Number(bit)) parts.push(MOD_NAMES[bit]);
    parts.push(key);
    return parts.join(" + ");
}

// Derive a category + tidy label from a bind description. A "Cat: label" prefix
// wins (e.g. "Workspace: Focus 5"); otherwise bucket by keywords.
function categorize(desc) {
    var m = desc.match(/^([A-Za-z][\w &/'-]*?):\s*(.+)$/);
    if (m) return { cat: m[1], label: m[2] };
    if (desc.endsWith("…") || desc.endsWith("...")) return { cat: "Menus", label: desc };
    var d = desc.toLowerCase();
    if (/volume|mute|media|player|track|brightness/.test(d)) return { cat: "Media", label: desc };
    if (/window|focus|swap|close|minimize|float|fullscreen|maximize/.test(d)) return { cat: "Window", label: desc };
    if (/workspace/.test(d)) return { cat: "Workspace", label: desc };
    if (/keyboard layout|screen|capture|hyprpicker|hex|picker/.test(d)) return { cat: "Utilities", label: desc };
    return { cat: "General", label: desc };
}

// Parse `hyprctl binds -j` for a given submap ("" = root) into ordered
// categories: [{ name, rows: [{ combo, desc }] }].
function parse(jsonText, submap, categoryOrder) {
    var binds;
    try { binds = JSON.parse(jsonText); } catch (e) { return []; }
    var seen = {};
    var groups = {};   // category -> [{ combo, desc }]
    for (var i = 0; i < binds.length; i++) {
        var b = binds[i];
        if (!b.description) continue;
        if ((b.submap || "") !== submap) continue;
        var c = combo(b.modmask || 0, b.key);
        var parts = categorize(b.description);
        var dedup = parts.cat + "|" + c + "|" + parts.label;
        if (seen[dedup]) continue;
        seen[dedup] = true;
        (groups[parts.cat] || (groups[parts.cat] = [])).push({ combo: c, desc: parts.label });
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

// Greedily balance categories across two columns by total height (rows+header).
function splitColumns(list) {
    var left = [], right = [];
    var lh = 0, rh = 0;
    var arr = list || [];
    for (var i = 0; i < arr.length; i++) {
        var c = arr[i];
        var h = c.rows.length + 1;
        if (lh <= rh) { left.push(c); lh += h; }
        else { right.push(c); rh += h; }
    }
    return [left, right];
}
