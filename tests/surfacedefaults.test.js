// Default placement requests a scene's `surfaces` declaration overrides
// (docs/scenes.md "Areas", services/PanelBus.md "Surfaces").
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { defaultFor } = loadLibrary("services/SurfaceDefaults.js");

test("notifications and toasts default to the last column's top-right", () => {
  for (const id of ["notifications", "toasts"]) {
    assert.deepEqual(defaultFor(id), { of: "column:last", scale: 0.33, align: "right", valign: "top" });
  }
});

test("centered dialogs default to work, at their own former screen-ratio scale", () => {
  assert.deepEqual(defaultFor("control"), { of: "work", scale: 0.72, align: "center", valign: "center" });
  assert.deepEqual(defaultFor("cheatsheet"), { of: "work", scale: 0.62, align: "center", valign: "center" });
  assert.deepEqual(defaultFor("workspaceswitcher"), { of: "work", scale: 0.42, align: "center", valign: "center" });
  assert.deepEqual(defaultFor("windowrename"), { of: "work", scale: 0.4, align: "center", valign: "center" });
  assert.deepEqual(defaultFor("obsidiancreate"), { of: "work", scale: 0.52, align: "center", valign: "center" });
});

test("systemcenter keeps its right-edge dock, capped to the work area", () => {
  assert.deepEqual(defaultFor("systemcenter"), { of: "work", scale: 0.34, align: "right", valign: "top" });
});

test("fixed-pixel-width surfaces get a near-zero scale so they keep their own width", () => {
  for (const [id, align] of [["classassigner", "center"], ["teamselector", "right"], ["sysmon", "center"]]) {
    const request = defaultFor(id);
    assert.equal(request.of, "work");
    assert.equal(request.align, align);
    assert.ok(request.scale > 0 && request.scale < 0.1, `${id} should barely grow with the area`);
  }
});

test("an unlisted surface defaults to a centered, work-capped box", () => {
  assert.deepEqual(defaultFor("whatever-nobody-declared"), { of: "work", scale: 1, align: "center", valign: "center" });
});
