.pragma library

// The announce phase of the reconcile contract (LEO-242): before a mode
// transition acts, the desk says what it is about to change and what it will
// take away — naming the RESOURCES, not just the mode, so "entering gaming"
// also reads as "stopping the sync". The verdicts and the deadline belong to
// the veto protocol (LEO-256); this file only builds what the announcement
// says.
//
// The declaration is the source of the taking: a mode revokes what it
// `remove`s — services stop, binding trees withdraw. Scene sets, forms and
// leases change, they do not take away, so they are not announced.

/** The resource kinds a transition can take away, in announcement order. */
var KINDS = ["services", "bindings"];

/** The human verb each kind names. */
var VERBS = { services: "stopping", bindings: "withdrawing" };

/** Same in the plural the bar can speak. */
var PLURAL = { services: "services", bindings: "keybinds" };

/**
 * What a mode's declaration takes away: [{ kind, id, verb }].
 *
 * [] means the transition takes nothing — entering a mode that only adds or
 * restyles itself has nothing to announce.
 */
function taken(spec) {
    const out = [];
    for (const kind of KINDS) {
        const delta = (spec || {})[kind] || {};
        for (const id of delta.remove || []) {
            out.push({ kind: kind, id: id, verb: VERBS[kind] });
        }
    }
    return out;
}

/** The line the announcement reads: "stopping linear-sync · withdrawing dofus". */
function sentence(takenList) {
    return (takenList || []).map(t => t.verb + " " + t.id).join(" · ");
}

/**
 * The announcement a transition owes the user, or null when it takes
 * nothing: { title, body } — the title reads the mode, the body reads
 * what is being taken away from it.
 */
function announce(spec, modeName) {
    const list = taken(spec);
    if (!list.length) return null;
    return {
        title: String(modeName || "") || "mode change",
        body: sentence(list),
        plural: list.length > 1
    };
}
