// The precedence rule that keeps focus.json trustworthy once a schedule can
// write it alongside a keybind and a timer: a manual choice holds until it
// expires or is cleared, and nothing automated may silently undo it. These
// tests pin that a manual hold blocks automated writers, that expiry releases
// it, and that a blocked schedule boundary is reported rather than dropped.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { decide } = loadLibrary("services/ModePrecedence.js");

const state = over => ({ mode: "neutral", until: null, source: null, set_at: null, ...over });

test("a manual current mode blocks a schedule proposal", () => {
    const current = state({ mode: "deep", source: "manual", until: null });
    const proposal = state({ mode: "chores", source: "schedule" });
    const r = decide(current, proposal, new Date());
    assert.equal(r.allowed, false);
});

test("a manual hold with no `until` holds indefinitely", () => {
    // Open-ended manual sessions only end at an explicit stop/set, never by a
    // schedule boundary rolling past.
    const current = state({ mode: "deep", source: "manual", until: null });
    const proposal = state({ mode: "media", source: "timer" });
    const farFuture = new Date("2099-01-01T00:00:00Z");
    assert.equal(decide(current, proposal, farFuture).allowed, false);
});

test("an expired manual hold yields to an automated proposal", () => {
    const current = state({ mode: "deep", source: "manual", until: "2026-09-14T10:00:00Z" });
    const proposal = state({ mode: "neutral", source: "schedule" });
    const after = new Date("2026-09-14T11:00:00Z");
    assert.equal(decide(current, proposal, after).allowed, true);
});

test("a manual hold not yet expired still blocks", () => {
    const current = state({ mode: "deep", source: "manual", until: "2026-09-14T10:00:00Z" });
    const proposal = state({ mode: "neutral", source: "schedule" });
    const before = new Date("2026-09-14T09:00:00Z");
    assert.equal(decide(current, proposal, before).allowed, false);
});

test("schedule beats a timer-set current mode", () => {
    // A calendar-derived schedule reflects a standing decision about the
    // week; a timer is a single countdown and should not outrank it.
    const current = state({ mode: "chores", source: "timer" });
    const proposal = state({ mode: "reflect", source: "schedule" });
    assert.equal(decide(current, proposal, new Date()).allowed, true);
});

test("schedule beats a schedule-set current mode", () => {
    // A later schedule boundary correcting an earlier one is exactly what a
    // calendar-derived schedule is for.
    const current = state({ mode: "chores", source: "schedule" });
    const proposal = state({ mode: "reflect", source: "schedule" });
    assert.equal(decide(current, proposal, new Date()).allowed, true);
});

test("a timer does not outrank a schedule-set current mode", () => {
    const current = state({ mode: "reflect", source: "schedule" });
    const proposal = state({ mode: "chores", source: "timer" });
    assert.equal(decide(current, proposal, new Date()).allowed, false);
});

test("a manual proposal always wins, even over an active manual hold", () => {
    // The user acting right now outranks everything, including their own
    // earlier choice.
    const current = state({ mode: "deep", source: "manual", until: null });
    const proposal = state({ mode: "game", source: "manual" });
    assert.equal(decide(current, proposal, new Date()).allowed, true);
});

test("a store with no source/set_at is treated as a manual hold", () => {
    // Backward compatibility: an older store on disk predates provenance and
    // must not become an accidental free-for-all for automation.
    const current = state({ mode: "deep", source: null, until: null });
    const proposal = state({ mode: "chores", source: "schedule" });
    assert.equal(decide(current, proposal, new Date()).allowed, false);
});

test("a schedule boundary skipped by a manual hold is reported, not dropped", () => {
    const current = state({ mode: "deep", source: "manual", until: null });
    const proposal = state({ mode: "chores", source: "schedule" });
    const r = decide(current, proposal, new Date());
    assert.equal(r.allowed, false);
    assert.equal(r.skipped.reason, "manual-hold");
    assert.deepEqual(r.skipped.proposal, proposal);
});

test("an allowed write reports nothing skipped", () => {
    const current = state({ mode: "neutral", source: "schedule" });
    const proposal = state({ mode: "chores", source: "schedule" });
    assert.equal(decide(current, proposal, new Date()).skipped, null);
});
