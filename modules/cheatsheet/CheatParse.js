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
    // Workspace before window: "focus workspace 5" matches both, and it is a
    // workspace bind. Most real binds carry a "Workspace:" prefix and never
    // reach here, which is why the precedence went unnoticed.
    if (/workspace/.test(d)) return { cat: "Workspace", label: desc };
    if (/window|focus|swap|close|minimize|float|fullscreen|maximize/.test(d)) return { cat: "Window", label: desc };
    if (/keyboard layout|screen|capture|hyprpicker|hex|picker/.test(d)) return { cat: "Utilities", label: desc };
    return { cat: "General", label: desc };
}

// Binds carry no context field — only `description` and `submap` — so a
// bind's relevance to the live desk (workspace/group) has to be inferred from
// the same text `categorize()` already buckets on. This is deliberately the
// fuzzy, no-hypr-change option: a bind is "gaming-scoped" if it landed in the
// Dofus category (the category itself is keyword-derived from the
// description), and "group-scoped" if its description mentions a group
// literally. Precise would mean tagging binds at the source (a convention like
// a trailing "[gaming]"/"[group]" marker in the Lua description, enforced by
// hypr/hypr/lib/submap.lua) — a hypr-repo change, out of reach here.
function contextTag(cat, desc) {
    if (cat === "Dofus") return "gaming";
    if (/\bgroup(ed|s)?\b/i.test(desc)) return "group";
    return null;
}

// Does a bind belong in the current desk context? `ctx.gaming` is true only
// on the gaming workspace; `ctx.grouped` only while a Hyprland group is
// focused. Anything untagged is context-free and always shown.
function matchesContext(tag, ctx) {
    ctx = ctx || {};
    if (tag === "gaming") return !!ctx.gaming;
    if (tag === "group") return !!ctx.grouped;
    return true;
}

// Parse `hyprctl binds -j` for a given submap ("" = root) into ordered
// categories: [{ name, rows: [{ combo, desc }] }]. `ctx` (optional) filters
// out binds whose inferred context doesn't match the live desk — they are
// dropped entirely, not greyed, so a hidden row never costs a read.
function parse(jsonText, submap, categoryOrder, ctx) {
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
        if (!matchesContext(contextTag(parts.cat, parts.label), ctx)) continue;
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

// Render the four-tuple context as a breadcrumb. Any missing piece (no
// focused window, no group, layout not yet probed) reads as "—" rather than
// disappearing, so the shape of the tuple stays legible at a glance.
function breadcrumb(ctx) {
    ctx = ctx || {};
    var dash = "—";
    var group = ctx.grouped ? "grouped" : dash;
    return [ctx.workspace || dash, ctx.windowClass || dash, group, ctx.layout || dash].join(" › ");
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
