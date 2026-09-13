// Pure calendar math backing CalendarPill/CalendarPanel — month grid layout
// and entry lookup, decoupled from wherever entries eventually come from
// (local JSON today, CalDAV later) so both sides can be tested independently.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { monthGrid, entriesOn, countsByDate } = loadLibrary(
    "modules/bar/CalendarSource.js",
    ["monthGrid", "entriesOn", "countsByDate"]
);

test("monthGrid always returns 6 weeks of 7 days", () => {
    const cells = monthGrid(2026, 1); // February 2026
    assert.equal(cells.length, 42);
});

test("monthGrid weeks start on Monday", () => {
    const cells = monthGrid(2026, 1);
    // 2026-02-01 is a Sunday; the grid's first cell should be the Monday before it.
    const first = new Date(cells[0].date);
    assert.equal(first.getUTCDay(), 1);
});

test("every day of the target month is marked inMonth, lead/trail days are not", () => {
    const cells = monthGrid(2026, 1);
    const inMonthDays = cells.filter(c => c.inMonth).map(c => c.day);
    assert.equal(inMonthDays.length, 28); // Feb 2026 is not a leap year
    assert.equal(inMonthDays[0], 1);
    assert.equal(inMonthDays.at(-1), 28);
});

test("entriesOn filters by exact date and sorts all-day entries first", () => {
    const entries = [
        { date: "2026-02-05", time: "14:00", title: "call" },
        { date: "2026-02-05", time: "", title: "birthday" },
        { date: "2026-02-06", time: "09:00", title: "elsewhere" }
    ];
    const rows = entriesOn(entries, "2026-02-05");
    assert.deepEqual(rows.map(r => r.title), ["birthday", "call"]);
});

test("entriesOn tolerates a missing entries array", () => {
    assert.deepEqual(entriesOn(undefined, "2026-02-05"), []);
});

test("countsByDate tallies entries per date", () => {
    const entries = [
        { date: "2026-02-05", title: "a" },
        { date: "2026-02-05", title: "b" },
        { date: "2026-02-06", title: "c" }
    ];
    assert.deepEqual(countsByDate(entries), { "2026-02-05": 2, "2026-02-06": 1 });
});
