// LEO-340: the bar's side inset mirrors each monitor's published outer gap.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { insetFor } = loadLibrary("services/BarGaps.js");

test("a monitor with a published gap uses it, left and right independently", () => {
    const store = { monitors: { "DP-1": { left: 40, right: 40 }, "DP-2": { left: 14, right: 14 } } };
    assert.deepEqual(insetFor(store, "DP-1", 24), { left: 40, right: 40 });
    assert.deepEqual(insetFor(store, "DP-2", 24), { left: 14, right: 14 });
});

test("a monitor absent from the store falls back to the bar's default inset", () => {
    const store = { monitors: { "DP-1": { left: 40, right: 40 } } };
    assert.deepEqual(insetFor(store, "eDP-1", 24), { left: 24, right: 24 });
});

test("an empty store falls back for every screen", () => {
    assert.deepEqual(insetFor({}, "DP-1", 16), { left: 16, right: 16 });
    assert.deepEqual(insetFor(null, "DP-1", 16), { left: 16, right: 16 });
});

test("a malformed entry (missing left/right) falls back rather than reading undefined", () => {
    const store = { monitors: { "DP-1": { left: 40 } } };
    assert.deepEqual(insetFor(store, "DP-1", 24), { left: 24, right: 24 });
});

test("laptop-solo: both monitors take the same published gap", () => {
    const store = { monitors: { "eDP-1": { left: 8, right: 8 }, "HDMI-A-1": { left: 8, right: 8 } } };
    assert.deepEqual(insetFor(store, "eDP-1", 24), { left: 8, right: 8 });
    assert.deepEqual(insetFor(store, "HDMI-A-1", 24), { left: 8, right: 8 });
});
