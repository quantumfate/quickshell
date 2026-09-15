.pragma library

// The routed notification centre's display model (LEO-240).
//
// History is never conditional — every entry carries the verdict and the rule
// that decided it — so the panel can answer what a mode hid, not just what it
// showed. These are the words the cards read, in one place, so the panel and
// any future surface say the same thing.

/** Tier names, in the resolution chain's own order. */
function tierWord(tier) {
    switch (tier) {
        case 1: return "desktop entry";
        case 2: return "hyprfocus source";
        case 3: return "category";
        case 4: return "app name";
        default: return "unknown";
    }
}

/**
 * The sender line a card opens with.
 *
 * The resolved source is what routing keyed on, so the panel names it. The
 * self-reported app name appears only where the source came from the name's
 * own claim (tier 4+) — recorded as untrusted rather than mysterious.
 */
function sender(entry) {
    const source = entry.source || "unknown";
    const trusted = entry.trusted !== false;
    if (trusted) return source;
    return entry.appName ? source + " (claimed: " + entry.appName + ")" : source + " (untrusted)";
}

/** The tier the identity resolved at, e.g. "desktop entry" — about the how, not the what. */
function tierLine(entry) {
    return tierWord(entry.tier);
}

/**
 * What happened to the entry, from the verdict the mode applied.
 *
 * "shown" is the plain case; queued/digested/held read what the active
 * policy asked for, name the rule that decided, and note when a critical
 * escalated out of silence.
 */
function routeLine(entry) {
    const route = entry.route || "shown";
    if (route === "shown" || route === "") return "shown";
    if (route === "dnd") return "held by do-not-disturb";
    if (route === "mood") return "held by the mode's policy";
    if (route.lastIndexOf("mode:", 0) === 0) {
        const verdict = route.slice(5);
        const escalated = entry.escalated ? " (critical escalated)" : "";
        const rule = entry.rule && entry.rule !== "default" ? " by rule '" + entry.rule + "'" : "";
        switch (verdict) {
            case "queue": return "queued" + rule + escalated;
            case "digest": return "counted only" + rule + escalated;
            case "drop": return "dropped" + rule + escalated;
            default: return verdict + rule;
        }
    }
    return route;
}

/** The verdict badge a card carries, keyed the way history stores it. */
function verdict(route) {
    const r = route || "shown";
    if (r === "" || r === "shown") return "shown";
    if (r === "dnd") return "held";
    if (r === "mood") return "held";
    if (r.lastIndexOf("mode:", 0) === 0) return r.slice(5);
    return "shown";
}

/** The badge colour a card reads as: the verdict first, the shell level when no verdict decided. */
function verdictRole(route, level) {
    const v = verdict(route);
    switch (v) {
        case "drop": return "error";
        case "queue": return "pending";
        case "digest": return "pending";
        case "held": return "info";
        case "shown":
            if (level === "error") return "error";
            if (level === "success") return "success";
            return "accent";
        default: return "accent";
    }
}
