// Pure calendar math backing CalendarPill/CalendarPanel — month grid layout
// and entry lookup, decoupled from wherever entries eventually come from
// (local JSON today, CalDAV later) so both sides can be tested independently.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { monthGrid, entriesOn, countsByDate, addDays, ymOf, impliedMode, upcoming, durationLabel, freeBlocks } = loadLibrary(
    "modules/bar/CalendarSource.js",
    ["monthGrid", "entriesOn", "countsByDate", "addDays", "ymOf", "impliedMode", "upcoming", "durationLabel", "freeBlocks"]
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

test("monthGrid handles a leap-year February (29 days)", () => {
    const cells = monthGrid(2028, 1); // 2028 is a leap year
    const inMonthDays = cells.filter(c => c.inMonth);
    assert.equal(inMonthDays.length, 29);
    assert.equal(inMonthDays.at(-1).day, 29);
});

test("monthGrid's trailing days roll into the next month correctly at a year boundary", () => {
    const cells = monthGrid(2025, 11); // December 2025
    const last = cells.at(-1);
    // Dec 2025 ends on a Wednesday; the grid always has 6 full weeks, so the
    // trailing cells spill into January 2026.
    assert.ok(last.date > "2025-12-31");
    assert.equal(last.inMonth, false);
});

test("addDays crosses a month boundary", () => {
    assert.equal(addDays("2026-01-31", 1), "2026-02-01");
});

test("addDays crosses a leap-year February boundary", () => {
    assert.equal(addDays("2028-02-28", 1), "2028-02-29");
    assert.equal(addDays("2028-02-29", 1), "2028-03-01");
});

test("addDays walks backward across a year boundary", () => {
    assert.equal(addDays("2026-01-01", -1), "2025-12-31");
});

test("ymOf reads year/month(0-based) out of an ISO date", () => {
    assert.deepEqual(ymOf("2026-03-15"), { year: 2026, month: 2 });
});

test("impliedMode prefers an explicit entry.mode over any keyword", () => {
    const entry = { title: "review the deck", mode: "work" };
    assert.equal(impliedMode(entry), "work");
});

test("impliedMode falls back to a per-calendar default before guessing keywords", () => {
    const entry = { title: "standup", calendar: "work-cal" };
    assert.equal(impliedMode(entry, { "work-cal": "work" }), "work");
});

test("impliedMode guesses from a title keyword ('dofus raid' -> gaming)", () => {
    assert.equal(impliedMode({ title: "20:00 raid" }), "gaming");
    assert.equal(impliedMode({ title: "exam prep" }), "study");
});

test("impliedMode defaults to neutral with no signal at all", () => {
    assert.equal(impliedMode({ title: "team sync" }), "neutral");
});

test("impliedMode tolerates a missing/undefined entry", () => {
    assert.equal(impliedMode(undefined), "neutral");
});

test("upcoming returns entries at or after now, soonest first, capped at the limit", () => {
    const entries = [
        { date: "2026-02-05", time: "14:00", title: "later" },
        { date: "2026-02-05", time: "09:00", title: "past" },
        { date: "2026-02-06", time: "08:00", title: "tomorrow" }
    ];
    const rows = upcoming(entries, "2026-02-05", "10:00", 5);
    assert.deepEqual(rows.map(r => r.title), ["later", "tomorrow"]);
});

test("upcoming respects the limit", () => {
    const entries = [
        { date: "2026-02-05", time: "01:00", title: "a" },
        { date: "2026-02-05", time: "02:00", title: "b" },
        { date: "2026-02-05", time: "03:00", title: "c" }
    ];
    assert.equal(upcoming(entries, "2026-02-05", "00:00", 2).length, 2);
});

test("upcoming tolerates a missing entries array", () => {
    assert.deepEqual(upcoming(undefined, "2026-02-05", "00:00", 5), []);
});

test("durationLabel formats hours/minutes and clamps negatives to 0m", () => {
    assert.equal(durationLabel(135), "2h 15m");
    assert.equal(durationLabel(60), "1h");
    assert.equal(durationLabel(45), "45m");
    assert.equal(durationLabel(-10), "0m");
});

test("freeBlocks reports the gaps between timed entries within the day window", () => {
    const entries = [
        { date: "2026-02-05", time: "09:00", title: "standup", durationMinutes: 30 },
        { date: "2026-02-05", time: "13:00", title: "lunch review", durationMinutes: 45 }
    ];
    const gaps = freeBlocks(entries, 6, 24);
    // 06:00-09:00, 09:30-13:00, 13:45-24:00
    assert.equal(gaps.length, 3);
    assert.equal(gaps[0].minutes, 180);
    assert.equal(gaps[1].minutes, 210);
});

test("freeBlocks with no timed entries is the whole day window as one gap", () => {
    const gaps = freeBlocks([], 6, 24);
    assert.equal(gaps.length, 1);
    assert.equal(gaps[0].minutes, (24 - 6) * 60);
});
