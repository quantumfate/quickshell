.pragma library

// Theme packs: one interchange language, adapters on the outside (LEO-289).
//
// A pack is a family, a variant is one palette in it, and each variant speaks
// base24 — the terminal-compatible core, whose slot meanings are verified
// against tinted-theming/base24/styling.md rather than recalled. On top of
// the slots the derivation reads the shell's semantic roles, so surfaces
// reference roles and never colours: the indirection that keeps element
// combinations consistent rather than assembled by accident.
//
// base24 alone is one ramp too short for this desk — the shell reads six
// surface tiers and the subtext/overlay steps base24 does not carry — so a
// variant may carry a `ramp` beside its slots. A ramp absent is a degraded
// palette, never an error: the derivation inherits from the nearest slot.

/** The base24 slot set, in reading order. */
var SLOTS = [
    "base00", "base01", "base02", "base03", "base04", "base05",
    "base06", "base07", "base08", "base09", "base0a", "base0b",
    "base0c", "base0d", "base0e", "base0f",
    "base10", "base11", "base12", "base13", "base14", "base15",
    "base16", "base17"
];

/** The ramp steps the slots skip; the only names a `ramp` may carry. */
var RAMP = ["subtext0", "subtext1", "overlay0", "overlay1", "overlay2"];

/** The accent roles a mode may lease, and where a pack's mapping looks. */
var ACCENT_ROLES = ["lavender", "blue", "peach", "mauve", "green", "pink", "teal"];

/**
 * The shell's semantic roles, derived from a variant's slots and ramp.
 *
 * Every widget reads these, so the pack never leaks slot names into widgets.
 * `accent`/`accentAlt` are the pack's own accent-map choice (see
 * `accentHue`); everything else is fixed vocabulary over the slot set.
 */
function variants(pack) {
    return (pack && pack.variants) || {};
}

function roleTable(pack, variant) {
    var s = variant.slots || {};
    var r = variant.ramp || {};
    var accents = pack.accents || {};
    return {
        background: s.base00,
        backgroundAlt: s.base01,
        surface: s.base02,
        surfaceAlt: s.base03,
        border: s.base04,
        overlay: r.overlay0 ?? s.base03,
        text: s.base05,
        subtext: r.subtext0 ?? s.base05,
        subtextAlt: r.subtext1 ?? s.base05,
        scrim: s.base11,
        inset: s.base11,
        success: s.base0b,
        warning: s.base0a,
        error: s.base08,
        info: s.base0d,
        pending: s.base09,
        accentSecondary: s.base0c,
        accentAlt: accents.lavender ? s[accents.lavender] : s.base07
    };
}

/**
 * The palette a variant renders in full: the roles plus the seven accent
 * hues the mode lease may pick, resolved per the pack's accent map.
 */
function palette(pack, id) {
    var variant = variants(pack)[id];
    if (!variant) return null;
    var table = roleTable(pack, variant);
    var accents = pack.accents || {};
    for (var i = 0; i < ACCENT_ROLES.length; i++) {
        var role = ACCENT_ROLES[i];
        // A pack may name its slots in any letter case; the storage shape is
        // lowercase.
        var slot = accents[role] && accents[role].toLowerCase();
        table[role] = slot ? variant.slots[slot] : table[role];
    }
    return table;
}

/**
 * The accent colour a mode's `accent_role` names. Never fails: an unknown
 * role, or a role the pack does not map, reads as mauve.
 */
function accentHue(pack, variantId, role) {
    var table = palette(pack, variantId);
    if (!table) return null;
    return table[role] ?? table.mauve;
}

/**
 * Which variant answers a need for one half of the day/night cycle.
 *
 * The chain runs: the variant's own counterpart (several darks often share
 * one light), then the pack's any-variant of that kind, then the variant
 * already in hand — a desk with a theme it cannot pair beats a desk with no
 * theme. A pack offering only one kind is not an error; the cycle takes what
 * is there.
 */
function counterpart(pack, variantId, want) {
    var variant = variants(pack)[variantId];
    if (!variant) return null;
    if (variant.kind === want) return variantId;
    var named = variant["light-counterpart"] && variants(pack)[variant["light-counterpart"]];
    if (named && named.kind === want) return variant["light-counterpart"];
    var any = null;
    for (var id in variants(pack)) {
        if (variants(pack)[id].kind === want) { any = id; break; }
    }
    if (any) return any;
    return variantId;
}

/**
 * The pack's contract, as a list of human-readable problems; empty means the
 * pack is well-formed enough to load. This is the install-time validation:
 * a pack that cannot fill its slot set, or that renders two modes
 * identically, is not installable.
 */
function lint(pack) {
    var problems = [];
    if (!pack || !pack.pack) return ["no pack name"];
    if (!pack.accents || ACCENT_ROLES.some(r => pack.accents[r] === undefined)) {
        problems.push("accents does not name all seven roles the shell can lease");
    }
    var found = variants(pack);
    if (Object.keys(found).length === 0) problems.push("no variants");
    for (const id in found) {
        const variant = found[id];
        for (const slot of SLOTS) {
            if (!variant.slots || !variant.slots[slot]) problems.push(`${id} is missing slot ${slot}`);
        }
        const r = variant.ramp || {};
        for (const name of Object.keys(r)) {
            if (RAMP.indexOf(name) < 0) problems.push(`${id}.ramp has unknown step ${name}`);
        }
        if (variant.kind === "dark" && variant["light-counterpart"] && !found[variant["light-counterpart"]]) {
            problems.push(`${id} names its counterpart '${variant["light-counterpart"]}' but the pack does not carry it`);
        }
    }
    if (pack.accents) {
        const hues = {};
        for (const role of ACCENT_ROLES) {
            const slot = pack.accents[role];
            if (slot && !SLOTS.includes(slot)) problems.push(`accent '${role}' names unknown slot '${slot}'`);
            hues[role] = slot;
        }
        const seen = {};
        for (const role of ACCENT_ROLES) {
            const slot = pack.accents[role];
            if (seen[slot]) problems.push(`accents '${seen[slot]}' and '${role}' share slot '${slot}' — two modes would render identically`);
            else seen[slot] = role;
        }
    }
    return problems;
}
