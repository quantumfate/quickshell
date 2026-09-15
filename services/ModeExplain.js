.pragma library

// The mode panel's explain half (LEO-280): the declaration, as a readable
// desk rather than raw JSON — provenance of the pointer, what a mode admits
// and withholds, and what it leases. One file so the panel (and any other
// surface) says the same words; the explain never invents what the
// declaration does not say. What a transition takes away is the announce
// model's own line (ModeAnnounce), not a second answer.

/** The pointer's story: who set the mode, and when. */
function provenance(pointer, until) {
    const segs = [];
    const who = (pointer && pointer.source) || "manual";
    segs.push("set by " + who);
    const time = pointer && pointer.set_at;
    if (time) {
        const d = new Date(time);
        segs.push(d.toLocaleString(undefined, {
            hour: "2-digit", minute: "2-digit", month: "short", day: "numeric"
        }));
    }
    if (until) segs.push("until " + until);
    return segs.join(", ");
}

/**
 * A mode's declaration as readable rows: [{ label, value }]. [] for an
 * undeclared mode — the panel says so itself rather than showing rows of
 * nothing.
 *
 * Only what the declaration says, mirroring the announce line's honesty:
 * `only` is read as the list it names, never as an implied prohibition of
 * everything not named; `remove` names the taking.
 */
function rows(spec) {
    if (!spec) return [];
    const out = [];

    // Services: what starts when the mode runs, and what goes away.
    const svc = spec.services || {};
    const admitted = (svc.only || []).concat(svc.add || []);
    if (admitted.length) out.push({ label: "services", value: "admits " + admitted.join(", ") });
    if ((svc.remove || []).length)
        out.push({ label: "services", value: "stops " + svc.remove.join(", ") });

    // Binding trees and workspaces: what the mode takes away, and what
    // narrows to stay.
    for (const kind of ["bindings", "workspaces"]) {
        const delta = spec[kind] || {};
        if (delta.only) out.push({ label: kind, value: "only " + delta.only.join(", ") });
        if ((delta.add || []).length) out.push({ label: kind, value: "adds " + delta.add.join(", ") });
        if ((delta.remove || []).length) out.push({ label: kind, value: "withdraws " + delta.remove.join(", ") });
    }

    // The leases: how the desk wants to look while this mode runs.
    const pres = spec.presentation || {};
    const leases = [];
    if (pres.palette) leases.push("palette " + pres.palette);
    if (pres.wallpaper) leases.push("wallpaper " + pres.wallpaper);
    if (leases.length) out.push({ label: "leases", value: leases.join(" · ") });

    // Notification routing for the mode, keyed by source id: the default and
    // the explicit rules, named as data.
    const notify = spec.notify || {};
    const rules = Object.keys(notify).filter(k => k !== "default");
    const segs = [];
    if (notify.default) segs.push(notify.default + " unless a rule says otherwise");
    if (rules.length) segs.push("rules: " + rules.join(", "));
    if (segs.length) out.push({ label: "notifications", value: segs.join(" · ") });

    return out;
}
