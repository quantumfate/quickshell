// Surfaces are placed in published areas (hypr repo docs/scenes.md "Areas"):
// a scene declares `surfaces = { id = { of, scale, align, valign } }`, and
// this module resolves that against the hypr-published `geometry.areas`
// entry for the surface's screen, plus its own content size, into a
// monitor-local box. See services/SurfacePlacement.js for the contract.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { boxOf, resolveArea, place, restingArea } = loadLibrary("services/SurfacePlacement.js");

const corners = (x, y, w, h) => ({
  top_left: { x, y },
  top_right: { x: x + w, y },
  bottom_left: { x, y: y + h },
  bottom_right: { x: x + w, y: y + h },
});

const areas = {
  scene: "code",
  work: corners(16, 58, 1000, 800),
  columns: {
    1: corners(16, 58, 400, 800),
    2: corners(416, 58, 600, 800),
  },
};

test("boxOf: a corners object becomes an x/y/width/height box", () => {
  assert.deepEqual(boxOf(corners(10, 20, 300, 400)), { x: 10, y: 20, width: 300, height: 400 });
});

test("resolveArea: 'work' resolves to the area's work box", () => {
  assert.deepEqual(resolveArea(areas, "work"), { x: 16, y: 58, width: 1000, height: 800 });
});

test("resolveArea: 'column:<order>' resolves that column", () => {
  assert.deepEqual(resolveArea(areas, "column:2"), { x: 416, y: 58, width: 600, height: 800 });
});

test("resolveArea: 'column:first'/'column:last' resolve by numeric order", () => {
  assert.deepEqual(resolveArea(areas, "column:first"), { x: 16, y: 58, width: 400, height: 800 });
  assert.deepEqual(resolveArea(areas, "column:last"), { x: 416, y: 58, width: 600, height: 800 });
});

test("resolveArea: an unknown column falls back to work", () => {
  assert.deepEqual(resolveArea(areas, "column:9"), { x: 16, y: 58, width: 1000, height: 800 });
});

test("resolveArea: 'column:first'/'last' with no columns falls back to work", () => {
  const noColumns = { work: areas.work, columns: {} };
  assert.deepEqual(resolveArea(noColumns, "column:first"), { x: 16, y: 58, width: 1000, height: 800 });
});

test("resolveArea: a missing areas entry answers null", () => {
  assert.equal(resolveArea(null, "work"), null);
  assert.equal(resolveArea(undefined, "column:last"), null);
  assert.equal(resolveArea({}, "work"), null);
});

test("place: scale picks the area fraction when it exceeds content size", () => {
  const area = { x: 0, y: 0, width: 1000, height: 800 };
  const box = place(area, { scale: 0.5, align: "left", valign: "top" }, { width: 100, height: 50 });
  assert.deepEqual(box, { x: 0, y: 0, width: 500, height: 50 });
});

test("place: content width wins over a scale that would shrink below it", () => {
  const area = { x: 0, y: 0, width: 1000, height: 800 };
  const box = place(area, { scale: 0.05, align: "left" }, { width: 200, height: 50 });
  assert.equal(box.width, 200);
});

test("place: width caps at the area's width and warns once with the overflow", () => {
  const area = { x: 0, y: 0, width: 300, height: 800 };
  const warnings = [];
  const box = place(area, { scale: 1 }, { width: 500, height: 50 }, (msg) => warnings.push(msg), "notifications");
  assert.equal(box.width, 300);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /notifications/);
  assert.match(warnings[0], /200px/);
});

test("place: height caps at the area's height and warns once with the overflow", () => {
  const area = { x: 0, y: 0, width: 1000, height: 100 };
  const warnings = [];
  const box = place(area, {}, { width: 50, height: 300 }, (msg) => warnings.push(msg), "toasts");
  assert.equal(box.height, 100);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /toasts/);
  assert.match(warnings[0], /200px/);
});

test("place: no warn callback is safe (defaults to a no-op)", () => {
  const area = { x: 0, y: 0, width: 100, height: 100 };
  assert.doesNotThrow(() => place(area, { scale: 1 }, { width: 500, height: 500 }));
});

test("place: align right/center and valign bottom/center position within the area", () => {
  const area = { x: 100, y: 200, width: 400, height: 300 };
  const content = { width: 100, height: 50 };
  const scale = { scale: 0.25 }; // 0.25 * 400 == content.width, so width stays 100
  assert.deepEqual(place(area, { ...scale, align: "right" }, content), { x: 400, y: 200, width: 100, height: 50 });
  assert.deepEqual(place(area, { ...scale, align: "center" }, content), { x: 250, y: 200, width: 100, height: 50 });
  assert.deepEqual(place(area, { ...scale, valign: "bottom" }, content), { x: 100, y: 450, width: 100, height: 50 });
  assert.deepEqual(place(area, { ...scale, valign: "center" }, content), { x: 100, y: 325, width: 100, height: 50 });
});

test("place: nothing ever extends outside the area, even doubly oversized", () => {
  const area = { x: 10, y: 10, width: 50, height: 50 };
  const box = place(area, { scale: 1, align: "right", valign: "bottom" }, { width: 200, height: 200 });
  assert.ok(box.x >= area.x && box.x + box.width <= area.x + area.width);
  assert.ok(box.y >= area.y && box.y + box.height <= area.y + area.height);
});

test("restingArea: monitor less the bar's reserved strip and the resting inset", () => {
  const box = restingArea({ width: 1920, height: 1080 }, 58, { left: 16, right: 16 });
  assert.deepEqual(box, { x: 16, y: 58, width: 1888, height: 1022 });
});

test("restingArea: never negative even if the inset/reserve exceeds the monitor", () => {
  const box = restingArea({ width: 100, height: 50 }, 80, { left: 60, right: 60 });
  assert.equal(box.width, 0);
  assert.equal(box.height, 0);
});
