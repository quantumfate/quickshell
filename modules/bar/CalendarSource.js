.pragma library
// Pure calendar math + entry lookup, kept separate from the QML so a future
// CalDAV source only has to produce the same `entries` shape — [{ date:
// "YYYY-MM-DD", time, title }] — that this file already knows how to grid and
// filter. Local-only for now (the bar's Clock.qml reads a plain JSON file).

function pad2(n) { return String(n).padStart(2, "0"); }
function isoDate(y, m, d) { return y + "-" + pad2(m + 1) + "-" + pad2(d); }

// A 6x7 grid of ISO date strings for `year`/`month` (0-based month), each
// tagged with whether it belongs to the target month — enough to render a
// month view with faded lead/trail days and no per-widget date math.
function monthGrid(year, month) {
    const first = new Date(year, month, 1);
    // Monday-first week, matching the rest of the shell's ISO-ish conventions.
    const lead = (first.getDay() + 6) % 7;
    const start = new Date(year, month, 1 - lead);
    const cells = [];
    for (let i = 0; i < 42; i++) {
        const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
        cells.push({
            date: isoDate(d.getFullYear(), d.getMonth(), d.getDate()),
            day: d.getDate(),
            inMonth: d.getMonth() === month
        });
    }
    return cells;
}

// entries: [{ date, time, title }] -> only those on `date` (ISO string),
// time-sorted, all-day (no time) entries first.
function entriesOn(entries, date) {
    return (entries || [])
        .filter(e => e.date === date)
        .sort((a, b) => (a.time || "").localeCompare(b.time || ""));
}

// date -> count of entries per ISO date, for the dot under each grid cell.
function countsByDate(entries) {
    const counts = {};
    for (const e of (entries || [])) counts[e.date] = (counts[e.date] || 0) + 1;
    return counts;
}

// ISO date string -> ISO date `days` away. Used by the month grid's h/j/k/l
// cursor so it never has to re-derive year/month rollover itself.
function addDays(iso, days) {
    const [y, m, d] = iso.split("-").map(Number);
    const dt = new Date(y, m - 1, d + days);
    return isoDate(dt.getFullYear(), dt.getMonth(), dt.getDate());
}

// ISO date -> { year, month(0-based) }, for jumping monthGrid() when a
// day-cursor move crosses a month boundary.
function ymOf(iso) {
    const [y, m] = iso.split("-").map(Number);
    return { year: y, month: m - 1 };
}

// Keyword -> implied focus mode, checked against a lowercased title. Order
// matters: first match wins, so put the more specific words first. Kept for
// the day `impliedMode` is redesigned and re-enabled (see below); dead code
// today since `impliedMode` never reaches it.
const MODE_KEYWORDS = [
    ["study", ["study", "studying", "exam", "revision", "flashcards"]],
    ["work", ["deep work", "write", "writing", "code", "coding", "design", "focus block", "review", "planning"]],
    ["gaming", ["game", "gaming", "raid", "dofus"]]
];

/**
 * The calendar-driven mode mapping contract: entry -> a declared mode id, or
 * null for "no opinion". Were it enabled, the intended precedence (most to
 * least specific) was:
 *   1. entry.mode          — explicit, always wins (the per-event override)
 *   2. calendarDefaults[entry.calendar] — a per-calendar default, for a feed
 *      (eventually CalDAV) whose calendar name already implies a mode
 *   3. a keyword match on the title (MODE_KEYWORDS)
 *   4. null — no signal, caller keeps whatever mode is already active
 *
 * DISABLED: this mechanism is undesigned — a calendar entry writing
 * the focus pointer needs its own precedence story (ModePrecedence.js) that
 * nobody has specified yet — so it always returns null, "no opinion", and
 * every caller must treat that as "derive nothing, do not touch focus.json".
 * The interface shape (entry, calendarDefaults) -> mode-id-or-null is kept so
 * a future design slots back in without a caller-side rewrite.
 */
function impliedMode(entry, calendarDefaults) {
    return null;
}

// entries -> the next `limit` (default 5) at or after `nowIso`/`nowTime`
// ("HH:MM"), soonest first. An entry with no time sorts as if at 00:00 —
// good enough for a local all-day entry; a CalDAV all-day event would want
// its own lane, but that is the later issue's problem.
function upcoming(entries, nowIso, nowTime, limit) {
    const nowKey = nowIso + "T" + (nowTime || "00:00");
    return (entries || [])
        .map(e => ({ entry: e, key: e.date + "T" + (e.time || "00:00") }))
        .filter(x => x.key >= nowKey)
        .sort((a, b) => a.key.localeCompare(b.key))
        .slice(0, limit || 5)
        .map(x => x.entry);
}

// "HH:MM" + minutes -> "HH:MM" the given number of minutes later, wrapping
// past midnight. Used to lay out today's timeline strip and free-block gaps
// without pulling in a date library for pure time-of-day arithmetic.
function timeToMinutes(time) {
    const [h, m] = (time || "00:00").split(":").map(Number);
    return h * 60 + m;
}

// minutes -> "1h 30m" / "45m" / "2h", for free-block callouts and event
// durations. Zero or negative collapses to "0m" rather than a blank string.
function durationLabel(minutes) {
    const total = Math.max(0, Math.round(minutes || 0));
    const h = Math.floor(total / 60);
    const m = total % 60;
    if (h === 0) return m + "m";
    if (m === 0) return h + "h";
    return h + "h " + m + "m";
}

// today's timed entries -> free gaps between `dayStartHour` and `dayEndHour`
// (default 06:00–24:00), each { startMinutes, endMinutes, minutes }. All-day
// entries (no time) are ignored — they don't occupy a slot on the timeline.
function freeBlocks(entries, dayStartHour, dayEndHour) {
    const startMin = (dayStartHour ?? 6) * 60;
    const endMin = (dayEndHour ?? 24) * 60;
    const busy = (entries || [])
        .filter(e => e.time)
        .map(e => {
            const s = Math.max(startMin, timeToMinutes(e.time));
            const dur = e.durationMinutes || 30;
            return { s, e: Math.min(endMin, s + dur) };
        })
        .sort((a, b) => a.s - b.s);

    const gaps = [];
    let cursor = startMin;
    for (const block of busy) {
        if (block.s > cursor) gaps.push({ startMinutes: cursor, endMinutes: block.s, minutes: block.s - cursor });
        cursor = Math.max(cursor, block.e);
    }
    if (cursor < endMin) gaps.push({ startMinutes: cursor, endMinutes: endMin, minutes: endMin - cursor });
    return gaps.filter(g => g.minutes > 0);
}
