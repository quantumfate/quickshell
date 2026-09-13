.pragma library
// Pure logic over projects-health.json (per-repo git status, produced outside
// this repo). Kept separate from ProjectsPill/ProjectsDashboard so the state
// mapping and summary math are covered by tests/projectshealth.test.js without
// a live Store.
//
// A repo's `state` is one of: ok, plain (tracked but not a git repo — NOT an
// error), timeout, missing, error.

// Semantic role qmllint/QML maps to a Theme colour; kept out of this file so
// it stays plain-data testable.
function roleFor(state) {
    switch (state) {
        case "ok": return "ok";
        case "plain": return "neutral";
        case "timeout": return "warn";
        case "missing": return "warn";
        case "error": return "error";
        default: return "neutral";
    }
}

// repos: { name: { state, dirty, ahead, behind, ... } }
// -> { total, byState: {ok,plain,timeout,missing,error}, dirtyTotal, worstRole }
// ,proj-health records `last_commit` as a unix timestamp, not an age: the file
// is written on a timer and read whenever a panel opens, so an age baked in at
// collection time would be wrong by however long the two are apart.
function ageOf(repo) {
    if (!repo || typeof repo.last_commit !== "number") return null;
    return Math.max(0, Math.floor(Date.now() / 1000) - repo.last_commit);
}

function summarize(repos) {
    const byState = { ok: 0, plain: 0, timeout: 0, missing: 0, error: 0 };
    let dirtyTotal = 0;
    const names = Object.keys(repos || {});
    for (const name of names) {
        const r = repos[name] || {};
        if (r.state in byState) byState[r.state]++;
        dirtyTotal += r.dirty || 0;
    }
    const worstRole = byState.error > 0 ? "error"
        : (byState.timeout > 0 || byState.missing > 0) ? "warn"
        : "ok";
    return { total: names.length, byState, dirtyTotal, worstRole };
}

// Seconds -> compact "3d"/"5h"/"12m"/"now". Negative/undefined -> "".
function fmtAge(seconds) {
    if (!(seconds >= 0)) return "";
    if (seconds < 60) return "now";
    const m = Math.floor(seconds / 60);
    if (m < 60) return m + "m";
    const h = Math.floor(m / 60);
    if (h < 24) return h + "h";
    return Math.floor(h / 24) + "d";
}

// Repo rows for the dashboard, name-sorted with worst-state-first as a
// secondary key so trouble surfaces at the top.
const STATE_RANK = { error: 0, timeout: 1, missing: 1, plain: 3, ok: 4 };
function sortedRows(repos) {
    const names = Object.keys(repos || {});
    return names
        .map(name => Object.assign({ name: name }, repos[name]))
        .sort((a, b) => (STATE_RANK[a.state] ?? 2) - (STATE_RANK[b.state] ?? 2) || a.name.localeCompare(b.name));
}
