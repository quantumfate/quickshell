// Pure logic behind the projects pill/dashboard: state -> colour role, the
// glance summary, and row ordering. `plain` (tracked but not a git repo) must
// never read as trouble — that's the one state this file exists to protect.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { roleFor, summarize, fmtAge, sortedRows, ageOf, collectionAge } = loadLibrary(
    "modules/bar/ProjectsHealth.js",
    ["roleFor", "summarize", "fmtAge", "sortedRows", "ageOf", "collectionAge"]
);

test("plain is neutral, never an error/warn role", () => {
    assert.equal(roleFor("plain"), "neutral");
});

test("every documented state maps to a role", () => {
    for (const s of ["ok", "plain", "timeout", "missing", "error"]) {
        assert.ok(roleFor(s), s);
    }
});

test("an unknown state degrades to neutral rather than throwing", () => {
    assert.equal(roleFor("bogus"), "neutral");
});

test("summarize counts every repo exactly once and totals dirty files", () => {
    const repos = {
        a: { state: "ok", dirty: 2 },
        b: { state: "plain", dirty: 0 },
        c: { state: "error", dirty: 1 }
    };
    const s = summarize(repos);
    assert.equal(s.total, 3);
    assert.equal(s.byState.ok, 1);
    assert.equal(s.byState.plain, 1);
    assert.equal(s.byState.error, 1);
    assert.equal(s.dirtyTotal, 3);
});

test("worstRole escalates to error only when a repo actually errors", () => {
    assert.equal(summarize({ a: { state: "ok" } }).worstRole, "ok");
    assert.equal(summarize({ a: { state: "timeout" } }).worstRole, "warn");
    assert.equal(summarize({ a: { state: "plain" } }).worstRole, "ok");
    assert.equal(summarize({ a: { state: "error" }, b: { state: "timeout" } }).worstRole, "error");
});

test("summarize tolerates a missing/empty repos map", () => {
    assert.deepEqual(summarize(undefined).byState, { ok: 0, plain: 0, timeout: 0, missing: 0, error: 0 });
    assert.equal(summarize({}).total, 0);
});

test("fmtAge picks the coarsest unit that stays readable", () => {
    assert.equal(fmtAge(10), "now");
    assert.equal(fmtAge(90), "1m");
    assert.equal(fmtAge(3700), "1h");
    assert.equal(fmtAge(90000), "1d");
    assert.equal(fmtAge(undefined), "");
    assert.equal(fmtAge(-5), "");
});

test("sortedRows puts trouble first and is otherwise alphabetical", () => {
    const repos = {
        zeta: { state: "ok" },
        alpha: { state: "error" },
        beta: { state: "ok" }
    };
    assert.deepEqual(sortedRows(repos).map(r => r.name), ["alpha", "beta", "zeta"]);
});

// The shape below is not a guess: it is a real record from ,proj-health, which
// is the only producer of this file. An earlier version of the widget read
// `repos` and `lastCommitAgeSec`, neither of which that script emits, so the
// dashboard would have sat empty forever without anything failing.
test("reads the shape ,proj-health actually writes", () => {
    const record = {
        collected_at: "2026-09-13T10:02:05Z",
        projects: {
            nvim: { state: "ok", branch: "main", ahead: 0, behind: 0, dirty: 0, last_commit: 1757000000 },
            logs: { state: "plain" },
            quickshell: { state: "ok", branch: "main", ahead: 0, behind: 0, dirty: 30, last_commit: 1757700000 }
        }
    };
    const rows = sortedRows(record.projects);
    assert.equal(rows.length, 3, "every project makes a row");
    assert.ok(rows.some(r => r.name === "quickshell" && r.dirty === 30));

    const summary = summarize(record.projects);
    assert.ok(summary, "a real record summarizes");

    // `plain` is tracked-but-not-a-repo. It must never read as a failure.
    const plain = rows.find(r => r.name === "logs");
    assert.equal(plain.state, "plain");
    assert.equal(ageOf(plain), null, "no commit, no age");

    const age = ageOf(record.projects.nvim);
    assert.ok(typeof age === "number" && age > 0, "age is derived at read time");

    const staleness = collectionAge(record.collected_at);
    assert.ok(typeof staleness === "number" && staleness > 0, "collection age is derived at read time, not baked in");
});

test("collectionAge tolerates a missing or unparsable collected_at", () => {
    assert.equal(collectionAge(undefined), null);
    assert.equal(collectionAge(""), null);
    assert.equal(collectionAge("not a date"), null);
});
