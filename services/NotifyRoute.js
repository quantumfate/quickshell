.pragma library

// Notification identity, then policy.
//
// Routing on application name does not work, and the reason is specific:
// `app_name` in the freedesktop spec is self-reported, unauthenticated free
// text. `notify-send` sets it to whatever `-a` says, or to nothing. Two
// programs can claim one name, a program can rename itself between releases,
// and a script has no name at all unless it invents one. A table keyed on that
// is unmaintainable, which is the symptom that prompted this.
//
// So identity is resolved through an ordered chain and policy keys on the
// result. The tier is reported alongside, so a sender that only resolves at the
// bottom is visible rather than mysterious.

/** Resolution tiers, most trustworthy first. */
var TIER = {
    DESKTOP_ENTRY: 1,   // the .desktop id, set by the toolkit, stable across releases
    HYPRFOCUS: 2,       // our own hint, mandated for everything we ship
    CATEGORY: 3,        // the spec's own vocabulary (email.arrived, im.received)
    APP_NAME: 4,        // last resort, and recorded as untrusted
    UNKNOWN: 5
};

function _hint(hints, key) {
    if (!hints) return "";
    var value = hints[key];
    return typeof value === "string" ? value.trim() : "";
}

/** A stable id: lowercase, and without the .desktop suffix a desktop entry carries. */
function _normalise(value) {
    return String(value).trim().toLowerCase().replace(/\.desktop$/, "");
}

/**
 * Resolve a notification's source.
 *
 * `n` is the shape Notify keeps: { appName, desktopEntry, hints }.
 * Returns { id, tier, trusted } — `trusted` is false when the id came from the
 * sender's own claim about its name rather than from something it could not
 * choose freely.
 */
function source(n) {
    n = n || {};
    var entry = _normalise(n.desktopEntry || _hint(n.hints, "desktop-entry"));
    if (entry) return { id: entry, tier: TIER.DESKTOP_ENTRY, trusted: true };

    var ours = _hint(n.hints, "x-hyprfocus-source");
    if (ours) return { id: _normalise(ours), tier: TIER.HYPRFOCUS, trusted: true };

    var category = _hint(n.hints, "category");
    if (category) return { id: _normalise(category), tier: TIER.CATEGORY, trusted: true };

    var name = _normalise(n.appName || "");
    if (name) return { id: name, tier: TIER.APP_NAME, trusted: false };

    return { id: "unknown", tier: TIER.UNKNOWN, trusted: false };
}

/**
 * What a notification does on screen, given the active mode's routes.
 *
 * Matching runs most specific first: the resolved source id, then the full
 * category, then the category's family (`email` for `email.arrived`), then the
 * mode's default. Urgency is never identity — it only ever qualifies severity.
 *
 * A critical notification escalates out of silence unless the mode says
 * otherwise. A mode that hides "battery at 2%" is not reducing distraction, it
 * is withholding something you needed; `allowCriticalSuppression` exists so
 * that is a deliberate choice rather than an accident of the default route.
 */
function verdict(resolved, n, routes) {
    routes = routes || {};
    n = n || {};

    var category = _hint(n.hints, "category");
    var family = category.indexOf(".") > 0 ? category.split(".")[0] : "";

    var decided = "";
    var rule = "";
    if (routes[resolved.id] !== undefined) {
        decided = routes[resolved.id];
        rule = resolved.id;
    } else if (category && routes[_normalise(category)] !== undefined) {
        decided = routes[_normalise(category)];
        rule = _normalise(category);
    } else if (family && routes[family] !== undefined) {
        decided = routes[family];
        rule = family;
    } else {
        decided = routes["default"] !== undefined ? routes["default"] : "show";
        rule = "default";
    }

    if (n.urgency === "critical" && decided !== "show" && !routes.allowCriticalSuppression) {
        return { verdict: "show", rule: rule, escalated: true };
    }
    return { verdict: decided, rule: rule, escalated: false };
}

/**
 * The record a history entry carries. History is never conditional: every
 * notification is recorded with the verdict applied to it, whatever the mode
 * said. Suppression governs what interrupts, never what is knowable afterwards
 * — a mode that hid something must be able to show you what it hid.
 */
function route(n, routes) {
    var resolved = source(n);
    var decision = verdict(resolved, n, routes);
    return {
        source: resolved.id,
        tier: resolved.tier,
        trusted: resolved.trusted,
        verdict: decision.verdict,
        rule: decision.rule,
        escalated: decision.escalated
    };
}
