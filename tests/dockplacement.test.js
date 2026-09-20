// LEO-420: placement math for a docked bar isle, driven by the `geometry`
// store's `docks[screen][isleId]` document (region/anchor/grow/orientation/
// state). Pure JS so every anchor/grow/clamp/state case is covered without a
// running shell — see services/DockPlacement.js for the contract.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { placeDock, shouldWarnClamp, resolveDockMode } = loadLibrary("services/DockPlacement.js");

const screen = { width: 1920, height: 1080 };
const smallIsle = { width: 100, height: 40 };

// Nine anchor points spanning a region's corners, edge-midpoints, and centre,
// each paired with a growth direction consistent with its position (an
// anchor on the region's bottom edge grows "up", away from the window below
// it, etc.) — the placements a real scene layout produces.
const region = { x: 0, y: 0, w: 300, h: 200 };
const nineCases = [
  { name: "top-left, grows down", anchor: { x: 0, y: 0 }, grow: "down", expect: { x: 0, y: 0 } },
  { name: "top-mid, grows down", anchor: { x: 100, y: 0 }, grow: "down", expect: { x: 100, y: 0 } },
  { name: "top-right, grows left", anchor: { x: 300, y: 0 }, grow: "left", expect: { x: 200, y: 0 } },
  { name: "mid-left, grows right", anchor: { x: 0, y: 80 }, grow: "right", expect: { x: 0, y: 80 } },
  { name: "centre, grows down", anchor: { x: 100, y: 80 }, grow: "down", expect: { x: 100, y: 80 } },
  { name: "mid-right, grows left", anchor: { x: 300, y: 80 }, grow: "left", expect: { x: 200, y: 80 } },
  { name: "bottom-left, grows up", anchor: { x: 0, y: 200 }, grow: "up", expect: { x: 0, y: 160 } },
  { name: "bottom-mid, grows up", anchor: { x: 100, y: 200 }, grow: "up", expect: { x: 100, y: 160 } },
  { name: "bottom-right, grows up", anchor: { x: 300, y: 200 }, grow: "up", expect: { x: 300, y: 160 } },
];

for (const c of nineCases) {
  test(`anchor case: ${c.name}`, () => {
    const dock = { region, anchor: c.anchor, grow: c.grow };
    const result = placeDock(dock, smallIsle, screen);
    assert.deepEqual({ x: result.x, y: result.y }, c.expect);
    assert.equal(result.clamped, false);
  });
}

test("growth axis: vertical (up/down) keeps anchor.x as the left edge", () => {
  const dock = { region, anchor: { x: 40, y: 100 }, grow: "down" };
  const result = placeDock(dock, smallIsle, screen);
  assert.equal(result.x, 40);
  assert.equal(result.y, 100);
});

test("growth axis: horizontal (left/right) keeps anchor.y as the top edge", () => {
  const dock = { region, anchor: { x: 40, y: 100 }, grow: "right" };
  const result = placeDock(dock, smallIsle, screen);
  assert.equal(result.x, 40);
  assert.equal(result.y, 100);
});

test("clamp: an isle bigger than its region forfeits the surplus and centres in the gutter", () => {
  const bigIsle = { width: 400, height: 300 }; // exceeds the 300x200 region
  const dock = { region, anchor: { x: 0, y: 0 }, grow: "down" };
  const result = placeDock(dock, bigIsle, screen);
  assert.equal(result.clamped, true);
  // Centred in the gutter would put both edges negative here (the isle is
  // bigger than the region on both axes), so the screen clamp pulls it back
  // to the top-left corner.
  assert.equal(result.x, 0);
  assert.equal(result.y, 0);
});

test("clamp: a raw placement that would leave the screen is pulled back inside it", () => {
  const dock = { region: { x: 0, y: 0, w: 50, h: 50 }, anchor: { x: 10, y: 10 }, grow: "up" };
  const result = placeDock(dock, smallIsle, screen);
  assert.equal(result.clamped, true);
  assert.ok(result.y >= 0);
  assert.ok(result.x + smallIsle.width <= screen.width);
});

test("shouldWarnClamp fires only on the false->true edge, once per state change", () => {
  assert.equal(shouldWarnClamp(false, true), true);
  assert.equal(shouldWarnClamp(true, true), false);   // already warned, no frame spam
  assert.equal(shouldWarnClamp(true, false), false);  // recovery is silent
  assert.equal(shouldWarnClamp(false, false), false);
});

test("resolveDockMode: no published document for this screen/isle is resting", () => {
  assert.equal(resolveDockMode(undefined, "bar.workspaces"), "resting");
  assert.equal(resolveDockMode({}, "bar.workspaces"), "resting");
});

test("resolveDockMode: an isle declared false is hidden", () => {
  assert.equal(resolveDockMode({ "bar.workspaces": false }, "bar.workspaces"), "hidden");
});

test("resolveDockMode: docked and fallback states pass through, unknown state rests", () => {
  assert.equal(resolveDockMode({ "bar.workspaces": { state: "docked" } }, "bar.workspaces"), "docked");
  assert.equal(resolveDockMode({ "bar.workspaces": { state: "fallback" } }, "bar.workspaces"), "fallback");
  assert.equal(resolveDockMode({ "bar.workspaces": { state: "resting" } }, "bar.workspaces"), "resting");
  assert.equal(resolveDockMode({ "bar.workspaces": { state: "weird" } }, "bar.workspaces"), "resting");
});

test("an isle taller than its gutter keeps its along-edge alignment", () => {
    // The desk's top gutter is thinner than a bar isle. Forfeiting the
    // surplus must not also re-centre the isle horizontally: it still hangs
    // off the corner the scene anchored it to.
    const dock = {
        region: { x: 100, y: 0, w: 800, h: 30 },
        anchor: { x: 100, y: 30 },
        grow: "up",
        orientation: "horizontal",
        state: "docked",
    };
    const placed = placeDock(dock, { width: 200, height: 48 }, { width: 2000, height: 1000 });
    assert.equal(placed.x, 100, "still flush with the window's left edge");
    assert.equal(placed.y, 0, "pinned against the screen edge the gutter faces");
    assert.equal(placed.clamped, true);
});
