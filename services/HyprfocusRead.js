.pragma library

// Reading a declaration, without resolving one.
//
// The distinction matters. Resolving a mode into a complete desk already
// exists twice — in Lua for the compositor and in Python for the command
// line — and a third implementation here could disagree with both about what
// a mode means, which is the divergence the whole design exists to remove.
//
// So this only reports what the declaration says in as many words. Anything
// needing the resolved truth asks `,hyprfocus resolve`.

/** Resource kinds carrying the only/add/remove delta grammar. */
var KINDS = ["workspaces", "bindings", "services", "projects"];

function _modes(declaration) {
    return (declaration && declaration.modes) || {};
}

/** Display name for a mode, falling back to its id so it is still named. */
function label(declaration, id) {
    var spec = _modes(declaration)[id];
    return spec && spec.name ? spec.name : id;
}

/** Every declared mode id, sorted, for a picker. */
function ids(declaration) {
    return Object.keys(_modes(declaration)).sort();
}

/** Whether the declaration actually has this mode. */
function known(declaration, id) {
    return !!_modes(declaration)[id];
}

/**
 * What a mode withholds, named rather than counted.
 *
 * Only `remove` is reported. A resource missing because of an `only` is
 * withheld just as surely, but knowing that needs the base and the resolver —
 * so this reports what it can see and does not guess at the rest. A surface
 * wanting the whole truth asks the CLI; a bar entry wants the headline.
 */
function withholds(declaration, id) {
    var spec = _modes(declaration)[id];
    if (!spec) return [];
    var out = [];
    for (var i = 0; i < KINDS.length; i++) {
        var delta = spec[KINDS[i]];
        var removed = (delta && delta.remove) || [];
        for (var j = 0; j < removed.length; j++) out.push(removed[j]);
    }
    return out;
}

/**
 * Whether a mode names an exclusive set for any kind, which is the signal that
 * `withholds` is telling less than the whole story.
 */
function narrows(declaration, id) {
    var spec = _modes(declaration)[id];
    if (!spec) return false;
    for (var i = 0; i < KINDS.length; i++) {
        var delta = spec[KINDS[i]];
        if (delta && delta.only) return true;
    }
    return false;
}

/**
 * Notification routing for a mode: the base's rules with the mode's merged on
 * top, keyed by resolved source id.
 *
 * This is a merge, not a resolution — one shallow layer over another, with no
 * delta grammar and nothing to close transitively. That is why it can live
 * here without becoming a third answer to what a mode means.
 */
function routes(declaration, id) {
    var base = (declaration && declaration.base && declaration.base.notify) || {};
    var spec = _modes(declaration)[id];
    var over = (spec && spec.notify) || {};
    var out = {};
    for (var key in base) out[key] = base[key];
    for (var key2 in over) out[key2] = over[key2];
    return out;
}
