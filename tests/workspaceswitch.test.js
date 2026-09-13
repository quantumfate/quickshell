// Pure logic behind the workspace switcher overlay (grouping windows by
// workspace, filtering by query) — the part that silently listing the wrong
// windows on the wrong workspace would be hardest to notice from the UI alone.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { buildRows, filterRows } = loadLibrary("modules/bar/WorkspaceSwitch.js", ["buildRows", "filterRows"]);

const workspaces = [
    { id: 2, name: "creative" },
    { id: 1, name: "code" },
    { id: 5, name: "" }
];
const windows = [
    { wsId: 1, title: "nvim" },
    { wsId: 1, title: "zsh" },
    { wsId: 2, title: "gimp" }
];

test("rows are sorted by workspace id, regardless of input order", () => {
    const rows = buildRows(workspaces, windows);
    assert.deepEqual(rows.map(r => r.id), [1, 2, 5]);
});

test("windows group under their own workspace only", () => {
    const rows = buildRows(workspaces, windows);
    assert.deepEqual(rows.find(r => r.id === 1).windows, ["nvim", "zsh"]);
    assert.deepEqual(rows.find(r => r.id === 2).windows, ["gimp"]);
    assert.deepEqual(rows.find(r => r.id === 5).windows, []);
});

test("a workspace with no configured icon falls back to its id, or a dot past 9", () => {
    const rows = buildRows([{ id: 5, name: "" }, { id: 12, name: "" }], []);
    assert.equal(rows.find(r => r.id === 5).icon, "5");
    assert.notEqual(rows.find(r => r.id === 12).icon, "12");
});

test("empty query returns every row unchanged", () => {
    const rows = buildRows(workspaces, windows);
    assert.deepEqual(filterRows(rows, ""), rows);
    assert.deepEqual(filterRows(rows, "   "), rows);
});

test("filter matches by id, name, or a window title on that workspace", () => {
    const rows = buildRows(workspaces, windows);
    assert.deepEqual(filterRows(rows, "2").map(r => r.id), [2]);
    assert.deepEqual(filterRows(rows, "code").map(r => r.id), [1]);
    assert.deepEqual(filterRows(rows, "GIMP").map(r => r.id), [2]);
    assert.deepEqual(filterRows(rows, "nvim").map(r => r.id), [1]);
});

test("no match yields an empty list rather than throwing", () => {
    const rows = buildRows(workspaces, windows);
    assert.deepEqual(filterRows(rows, "nonexistent"), []);
});
