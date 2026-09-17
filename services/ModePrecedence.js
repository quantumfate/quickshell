.pragma library

// Who may overwrite the active-mode pointer, and when.
//
// Once a keybind, a timer, and a calendar-derived schedule can all write
// focus.json, "who wins" stops being obvious. The rule here is the one that
// keeps the desk trustworthy: a manual choice — set by hand, at a keybind —
// holds until it expires or is explicitly cleared. Nothing automated may
// overwrite it in the meantime. Without this, the desk silently undoes a
// deliberate decision at the next calendar boundary, which is exactly the
// kind of surprise the system exists to prevent, and the fastest way for the
// user to stop trusting it.
//
// A `source`/`set_at` missing on disk (an older store, or a write nothing
// attributed) is treated as `manual` — a pointer of unknown origin is safer
// assumed deliberate than assumed safe to overwrite.
//
// Among automated writers, schedule outranks timer: a calendar-derived
// schedule reflects a standing decision about the week: a timer is a single
// countdown. A timer boundary should not undo what the schedule just set, but
// the schedule may still correct a timer's guess.

/** Precedence among automated sources, highest first. Manual is handled
 *  separately (see isManualHold) because its hold also depends on `until`,
 *  not just on who wrote it. */
var RANK = { schedule: 2, timer: 1 };

/** The default/resting mode: what a timed mode falls back to once it lapses
 *  and there is no `previous` to fall back to (`neutral` is no longer
 *  the fallback; it is now a hidden recovery mode only reachable by hand). */
var DEFAULT_MODE = "work";

function normaliseSource(source) {
    return source == null ? "manual" : source;
}

/**
 * True when the current pointer is a manual choice still in force: set by
 * hand (or of unknown origin) and either open-ended (`until` is null) or not
 * yet expired.
 */
function isManualHold(current, now) {
    current = current || {};
    if (normaliseSource(current.source) !== "manual") return false;
    if (current.until == null) return true;
    return new Date(current.until).getTime() > now.getTime();
}

/**
 * Decide whether `proposal` (a candidate write, e.g. { mode, until, source,
 * set_at }) may replace `current` (the pointer presently on disk).
 *
 * A manual proposal always wins — a keybind is the user acting right now, and
 * nothing outranks that. Anything else must first clear a manual hold on
 * `current`; if it does, automated sources are ranked among themselves so a
 * schedule boundary can correct a timer's guess but a timer cannot undo a
 * schedule.
 *
 * Returns `{ allowed, skipped }`. `skipped` is null when the write is
 * allowed (or there was nothing to skip); otherwise it names why the caller
 * did not apply the proposal, so a schedule boundary that loses to a manual
 * hold can be recorded rather than silently dropped.
 */
/**
 * The effective mode `pointer` (`{ mode, until, previous }`) reads as right
 * now: `mode` itself while `until` is unset or still ahead, else `previous`
 * (falling back to `DEFAULT_MODE` when there is none) — never `neutral`,
 * which only a manual write can put on the pointer.
 */
function effectiveMode(pointer, now) {
    now = now || new Date();
    pointer = pointer || {};
    var mode = pointer.mode || DEFAULT_MODE;
    var until = pointer.until;
    if (until == null || new Date(until).getTime() > now.getTime()) return mode;
    return pointer.previous || DEFAULT_MODE;
}

/**
 * The `previous` a write entering a TIMED mode (one with `until` set) should
 * record, given the pointer as it stands right now. Carries forward the
 * current pointer's own `previous` unchanged when the current mode is itself
 * timed and unexpired, rather than nesting a chain of timed modes; otherwise
 * records the current effective mode, exactly as `effectiveMode` reads it.
 */
function nextPrevious(current, now) {
    now = now || new Date();
    current = current || {};
    var until = current.until;
    var currentlyTimedUnexpired = until != null && new Date(until).getTime() > now.getTime();
    if (currentlyTimedUnexpired) return current.previous ?? null;
    return effectiveMode(current, now);
}

function decide(current, proposal, now) {
    now = now || new Date();
    current = current || {};
    proposal = proposal || {};

    if (proposal.source === "manual") {
        return { allowed: true, skipped: null };
    }

    if (isManualHold(current, now)) {
        return {
            allowed: false,
            skipped: { reason: "manual-hold", current: current, proposal: proposal }
        };
    }

    // Current is either non-manual, or a manual hold that has expired — in
    // the latter case it no longer outranks anything, so fall through to
    // ranking the automated sources against each other.
    var currentSource = normaliseSource(current.source);
    var currentRank = currentSource === "manual" ? 0 : (RANK[currentSource] || 0);
    var proposalRank = RANK[proposal.source] || 0;

    if (proposalRank >= currentRank) {
        return { allowed: true, skipped: null };
    }

    return {
        allowed: false,
        skipped: { reason: "outranked", current: current, proposal: proposal }
    };
}
