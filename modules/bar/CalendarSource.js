.pragma library
// Pure calendar math + entry lookup, kept separate from the QML so a future
// CalDAV source only has to produce the same `entries` shape — [{ date:
// "YYYY-MM-DD", time, title }] — that this file already knows how to grid and
// filter. Local-only for now (CalendarPill.qml reads a plain JSON file).

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
