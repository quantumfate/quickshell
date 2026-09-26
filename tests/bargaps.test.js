// An isle that is not docked rests at a fixed position that depends on its
// monitor only (LEO cross-repo "bars never dance"): the monitor's published
// base gap, else the bar's default. Never the scene, its gaps, or what was
// last published — that opt-in (`bar_follows_scene_gaps`) and the inset
// memory it needed are retired; see services/BarGaps.js's header.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { insetFor } = loadLibrary("services/BarGaps.js");

const monitors = {
  "DP-1": { left: 40, right: 40 },
  "DP-2": { left: 14, right: 14 },
};
const geometry = { monitors };

test("a monitor with a published gap uses it while the bar rests", () => {
  assert.deepEqual(insetFor(geometry, "DP-1", 24), { left: 40, right: 40 });
  assert.deepEqual(insetFor(geometry, "DP-2", 24), { left: 14, right: 14 });
});

test("a monitor absent from the store falls back to the bar's default inset", () => {
  assert.deepEqual(insetFor(geometry, "eDP-1", 24), { left: 24, right: 24 });
});

test("an empty or null store falls back for every screen", () => {
  assert.deepEqual(insetFor({}, "DP-1", 16), { left: 16, right: 16 });
  assert.deepEqual(insetFor(null, "DP-1", 16), { left: 16, right: 16 });
});

test("a malformed entry (missing a side) falls back per side", () => {
  const lopsided = { monitors: { "DP-1": { left: 40 } } };
  assert.deepEqual(insetFor(lopsided, "DP-1", 24), { left: 40, right: 24 });
});

test("laptop-solo: both monitors take the same published gap", () => {
  const store = {
    monitors: {
      "eDP-1": { left: 8, right: 8 },
      "HDMI-A-1": { left: 8, right: 8 },
    },
  };
  assert.deepEqual(insetFor(store, "eDP-1", 24), { left: 8, right: 8 });
  assert.deepEqual(insetFor(store, "HDMI-A-1", 24), { left: 8, right: 8 });
});

test("an explicit published zero is a real gap, not a fallback signal", () => {
  const store = { monitors: { "DP-1": { left: 0, right: 0 } } };
  assert.deepEqual(insetFor(store, "DP-1", 24), { left: 0, right: 0 });
});

test("the same monitor gives the same inset regardless of scene (bars never dance)", () => {
  // insetFor takes no scene input at all now — a scene switch on DP-1 cannot
  // change what this call returns for DP-1.
  assert.deepEqual(insetFor(geometry, "DP-1", 24), insetFor(geometry, "DP-1", 24));
});
