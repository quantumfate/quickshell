// LEO-420: placement math for a docked bar isle, driven by the `geometry`
// store's `docks[screen][isleId]` document (region/anchor/grow/orientation/
// state). Pure JS so every anchor/grow/clamp/state case is covered without a
// running shell — see services/DockPlacement.js for the contract.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { placeDock, shouldWarnClamp, resolveDockMode, isPlaced } = loadLibrary("services/DockPlacement.js");

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

test("clamp: an isle bigger than its region stays inside the screen, never over the window", () => {
  const bigIsle = { width: 400, height: 300 }; // exceeds the 300x200 region
  const dock = { region, anchor: { x: 0, y: 0 }, grow: "down" };
  const result = placeDock(dock, bigIsle, screen);
  assert.equal(result.clamped, true);
  // The gutter's inner edge is where the window starts, and the screen is a
  // hard second boundary even when the gutter is too small.
  assert.equal(result.y, 0, "the bar is clamped to the screen");
  assert.equal(result.x, 0, "the along-edge axis still starts where the anchor said");
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

// "fallback" is the publisher's word for "resolved, down the ladder" — it
// carries a full region/anchor/grow. Every scene puts two isles on one block's
// top gutter, so one of them is always the fallback; treating that as "no
// geometry, freeze where you were" is why a stepped-down isle never moved.
test("both resolved states carry geometry; resting and hidden do not", () => {
  assert.equal(isPlaced("docked"), true);
  assert.equal(isPlaced("fallback"), true);
  assert.equal(isPlaced("resting"), false);
  assert.equal(isPlaced("hidden"), false);
});

// `grow` settles only the growth axis. Along the gutter, the anchor may be the
// isle's start, middle or end — and reading an "end" anchor as a start put the
// isle a full width too far out, where the bounds clamp flattened it against
// the screen edge. That is exactly what happened to the clock in every scene.
test("align says which part of the isle the anchor point is", () => {
  const doc = (align) => ({
    region: { x: 0, y: 0, w: 1000, h: 60 },
    anchor: { x: 800, y: 60 },
    grow: "up",
    align: align,
  });
  const size = { width: 200, height: 40 };
  const screen = { width: 1000, height: 800 };
  assert.equal(placeDock(doc("start"), size, screen).x, 800);
  assert.equal(placeDock(doc("center"), size, screen).x, 700);
  assert.equal(placeDock(doc("end"), size, screen).x, 600);
});

test("align shifts along the gutter for a side dock too", () => {
  const doc = {
    region: { x: 940, y: 0, w: 60, h: 800 },
    anchor: { x: 940, y: 500 },
    grow: "right",
    align: "end",
  };
  const placed = placeDock(doc, { width: 40, height: 120 }, { width: 1000, height: 800 });
  assert.equal(placed.x, 940);
  assert.equal(placed.y, 380, "bottom-aligned: the anchor is the isle's end on the vertical run");
});

test("a document with no align predates the field and reads as a start anchor", () => {
  const doc = { region: { x: 0, y: 0, w: 1000, h: 60 }, anchor: { x: 800, y: 60 }, grow: "up" };
  assert.equal(placeDock(doc, { width: 200, height: 40 }, { width: 1000, height: 800 }).x, 800);
});

// The isle floats clear of the edge it stands on by the bar's own margin —
// the same clearance a resting isle keeps. On the growth axis only, by the
// sign of `grow`; standing flush on the screen edge is what it looked like
// without this.
test("edgeMargin is added or subtracted on the growth axis alone", () => {
  const region = { x: 0, y: 0, w: 1000, h: 200 };
  const size = { width: 100, height: 40 };
  const screen = { width: 1000, height: 800 };
  const at = (grow, anchor) => placeDock({ region, anchor, grow, align: "start" }, size, screen, 8);

  assert.deepEqual(at("down", { x: 300, y: 0 }), { x: 300, y: 8, clamped: false });
  assert.deepEqual(at("up", { x: 300, y: 200 }), { x: 300, y: 152, clamped: false });
  assert.deepEqual(at("right", { x: 0, y: 300 }), { x: 8, y: 300, clamped: false });
  assert.deepEqual(at("left", { x: 200, y: 300 }), { x: 92, y: 300, clamped: false });
});

// The gutter's inner edge is where a window starts. An isle drawn over a
// window is the one outcome placement must never produce, so an isle too big
// for its gutter overhangs the SCREEN edge (where the output clips it) rather
// than the window edge.
test("an isle never crosses the gutter's inner edge, whatever its size", () => {
  const region = { x: 0, y: 0, w: 1000, h: 60 };
  const screen = { width: 1000, height: 800 };
  const doc = { region, anchor: { x: 0, y: 0 }, grow: "down", align: "start" };

  const tall = placeDock(doc, { width: 100, height: 90 }, screen, 8);
  assert.ok(tall.y >= 0, "the bar stays on screen");
  assert.ok(tall.y + 90 <= screen.height, "the bar stays within the output");
  assert.equal(tall.clamped, true);

  const fits = placeDock(doc, { width: 100, height: 40 }, screen, 8);
  assert.equal(fits.y, 8, "one that fits keeps its edge margin");
  assert.ok(fits.y + 40 <= region.y + region.h);
});

test("a side gutter bounds the isle the same way, on its own axis", () => {
  const region = { x: 940, y: 0, w: 60, h: 800 };
  const screen = { width: 1000, height: 800 };
  const doc = { region, anchor: { x: 1000, y: 0 }, grow: "left", align: "start" };
  const wide = placeDock(doc, { width: 90, height: 100 }, screen, 8);
  assert.ok(wide.x >= 0, "the bar stays on screen");
  assert.ok(wide.x + 90 <= screen.width, "the bar stays within the output");
});

test("a document with no geometry places nothing instead of throwing", () => {
  const size = { width: 100, height: 40 };
  const screen = { width: 1000, height: 800 };
  assert.equal(placeDock({ state: "hidden" }, size, screen), null);
  assert.equal(placeDock({ state: "resting" }, size, screen), null);
  assert.equal(placeDock(undefined, size, screen), null);
});

test("a half-published or zero-sized hook document stays on the resting path", () => {
  const dock = { region, anchor: { x: NaN, y: 0 }, grow: "down" };
  assert.equal(placeDock(dock, smallIsle, screen), null);
  assert.equal(placeDock({ region, anchor: { x: 0, y: 0 }, grow: "down" }, smallIsle,
    { width: 0, height: 0 }), null);
});

test("an isle taller than its gutter keeps its along-edge alignment", () => {
    // The desk's top gutter is thinner than a bar isle. Forfeiting the
    // Surplus must not also re-centre the isle horizontally: it still starts
    // at the corner the scene anchored it to.
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

// The hug model (a window target): the isle sits on the window's edge and
// grows away from it, so the edge it must not cross is the one the window is
// on — which `grow` alone cannot say, since a `screen` dock on the same
// gutter grows the other way. `edge` is what separates them.
test("a hugged top dock is pinned by the window edge, not the screen edge", () => {
    const dock = {
        region: { x: 100, y: 0, w: 800, h: 30 },
        anchor: { x: 100, y: 30 },
        grow: "up",
        edge: "top",
        align: "start",
        state: "docked",
    };
    const placed = placeDock(dock, { width: 200, height: 48 }, { width: 2000, height: 1000 });
    assert.equal(placed.y, 0, "the surplus is clamped inside the screen");
    assert.equal(placed.x, 100, "still flush with the window's left edge");
});

test("a hugged bottom dock is pinned at the region's start", () => {
    const dock = {
        region: { x: 100, y: 770, w: 800, h: 30 },
        anchor: { x: 100, y: 770 },
        grow: "down",
        edge: "bottom",
        align: "start",
        state: "docked",
    };
    const placed = placeDock(dock, { width: 200, height: 48 }, { width: 2000, height: 800 });
   assert.ok(placed.y >= 0, "the bar stays on screen");
   assert.ok(placed.y + 48 <= 800, "the bar stays within the output");
});

test("resolveDockMode: a scene-owned widget is opt-in — absent means absent", () => {
  // The three always-on isles rest when a scene says nothing; anything else
  // appears only where a scene names it with an anchor.
  assert.equal(resolveDockMode({}, "bar.projects"), "hidden");
  assert.equal(resolveDockMode({ "bar.clock": false }, "dofus.roster"), "hidden");
  assert.equal(resolveDockMode({}, "bar.center"), "resting");
  assert.equal(resolveDockMode({}, "bar.clock"), "resting");
});

test("resolveDockMode: no map at all is an unpublished screen, not a refusal", () => {
  // A map that exists and does not name the isle is the scene declining it.
  // NO map is a screen the desk has not published for yet — a shell that just
  // started, a monitor mid-hotplug, a swept pass. Reading the two the same
  // way hid the tab strip on the very scenes that declare it.
  assert.equal(resolveDockMode(undefined, "bar.projects"), "resting");
  assert.equal(resolveDockMode(null, "dofus.roster"), "resting");
  assert.equal(resolveDockMode(undefined, "bar.clock"), "resting");
});

test("resolveDockMode: a scene that names a widget with an anchor places it", () => {
  const docks = { "bar.projects": { state: "docked", region: { x: 0, y: 0, w: 10, h: 10 } } };
  assert.equal(resolveDockMode(docks, "bar.projects"), "docked");
  assert.equal(isPlaced(resolveDockMode(docks, "bar.projects")), true);
});
