// Pure logic behind the workspace switcher overlay (grouping windows by
// workspace, filtering by query) and the bar's per-monitor workspace pill
// (LEO-343: order and icons come from the hyprfocus declaration, never a
// hardcoded name list) — the part that silently listing the wrong workspaces,
// in the wrong order, or with the wrong icon would be hardest to notice from
// the UI alone.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const {
    catalogOrder, modeOrder, iconFor, orderBy, canonical, barWorkspaces,
    selector, buildRows, filterRows, roleForScreen, activeName
} = loadLibrary("modules/bar/WorkspaceSwitch.js", [
    "catalogOrder", "modeOrder", "iconFor", "orderBy", "canonical",
    "barWorkspaces", "selector", "buildRows", "filterRows", "roleForScreen",
    "activeName"
]);

// A small fixture declaration: catalog order code, creative, media; "work"
// admits code on primary and media on secondary.
const declaration = {
    base: {
        scenes: {
            code: { icon: "C" },
            creative: {},
            media: { icon: "M" }
        }
    },
    modes: {
        work: {
            scenes: [
                { name: "code", monitor: "primary" },
                { name: "media", monitor: "secondary" }
            ]
        }
    }
};

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

test("catalogOrder() lists base.scenes in declaration order", () => {
    assert.deepEqual(catalogOrder(declaration), ["code", "creative", "media"]);
});

test("modeOrder() lists a mode's admitted scenes for one monitor role", () => {
    assert.deepEqual(modeOrder(declaration, "work", "primary"), ["code"]);
    assert.deepEqual(modeOrder(declaration, "work", "secondary"), ["media"]);
    assert.deepEqual(modeOrder(declaration, "ghost", "primary"), []);
});

test("iconFor() reads a scene's declared icon, falling back to id or a dot", () => {
    assert.equal(iconFor(declaration, "code", 1), "C");
    assert.equal(iconFor(declaration, "creative", 2), "2"); // declared, no icon set
    assert.equal(iconFor(declaration, "", 5), "5");
    assert.notEqual(iconFor(declaration, "", 12), "12"); // past 9: a dot, not the id
});

test("orderBy() merges id-backed twins into their named workspace", () => {
    const rows = orderBy(["code", "creative"], [
        { id: 1, name: "code" },
        { id: -1338, name: "code" },
        { id: 2, name: "creative" }
    ]);
    assert.deepEqual(rows.map(r => r.id), [-1338, 2]);
});

test("orderBy() keeps one row per undeclared id, sorted after, by id", () => {
    const rows = orderBy(["code"], [
        { id: 8, name: "8" },
        { id: 3, name: "" }
    ]);
    assert.deepEqual(rows.map(r => r.id), [3, 8]);
});

test("canonical() shows every real workspace in catalog order, undeclared ones after", () => {
    const rows = canonical(declaration, workspaces);
    assert.deepEqual(rows.map(r => r.id), [1, 2, 5]);
});

test("barWorkspaces() shows only this role's admitted scenes plus occupied others", () => {
    const rows = barWorkspaces(declaration, "work", "primary", [
        { id: 1, name: "code", occupied: true },
        { id: 2, name: "creative", occupied: true },  // admitted nowhere, but occupied
        { id: 3, name: "media", occupied: false }      // wrong role here, not shown
    ]);
    assert.deepEqual(rows.map(r => r.name), ["code", "creative"]);
});

test("barWorkspaces() drops an admitted-nowhere, unoccupied workspace", () => {
    const rows = barWorkspaces(declaration, "work", "primary", [
        { id: 1, name: "code", occupied: false },
        { id: 2, name: "creative", occupied: false }
    ]);
    assert.deepEqual(rows.map(r => r.id), [1]);
});

test("selector() speaks name for named workspaces, id for numeric ones", () => {
    assert.equal(selector({ id: -1338, name: "code" }), "name:code");
    assert.equal(selector({ id: 8, name: "8" }), "name:8");
    assert.equal(selector({ id: 5, name: "" }), "5");
});

test("buildRows() attaches each row's icon and its own windows only", () => {
    const rows = buildRows(declaration, canonical(declaration, workspaces), windows);
    assert.deepEqual(rows.find(r => r.id === 1).windows, ["nvim", "zsh"]);
    assert.deepEqual(rows.find(r => r.id === 2).windows, ["gimp"]);
    assert.deepEqual(rows.find(r => r.id === 5).windows, []);
    assert.equal(rows.find(r => r.id === 1).icon, "C");
});

test("empty query returns every row unchanged", () => {
    const rows = buildRows(declaration, canonical(declaration, workspaces), windows);
    assert.deepEqual(filterRows(rows, ""), rows);
    assert.deepEqual(filterRows(rows, "   "), rows);
});

test("filter matches by id, name, or a window title on that workspace", () => {
    const rows = buildRows(declaration, canonical(declaration, workspaces), windows);
    assert.deepEqual(filterRows(rows, "2").map(r => r.id), [2]);
    assert.deepEqual(filterRows(rows, "code").map(r => r.id), [1]);
    assert.deepEqual(filterRows(rows, "GIMP").map(r => r.id), [2]);
    assert.deepEqual(filterRows(rows, "nvim").map(r => r.id), [1]);
});

test("no match yields an empty list rather than throwing", () => {
    const rows = buildRows(declaration, canonical(declaration, workspaces), windows);
    assert.deepEqual(filterRows(rows, "nonexistent"), []);
});

test("roleForScreen() calls the geometry store's first monitor primary", () => {
    const monitors = { "DP-1": { left: 40, right: 40 }, "DP-2": { left: 8, right: 8 } };
    assert.equal(roleForScreen(monitors, "DP-1"), "primary");
    assert.equal(roleForScreen(monitors, "DP-2"), "secondary");
});

test("roleForScreen() calls an unrecognised screen secondary, an empty store primary", () => {
    assert.equal(roleForScreen({ "DP-1": {} }, "HDMI-A-1"), "secondary");
    assert.equal(roleForScreen({}, "eDP-1"), "primary");
    assert.equal(roleForScreen(undefined, "eDP-1"), "primary");
});

test("activeName() reads the focused row's name, which is the scene name", () => {
    const rows = [{ name: "code", active: false }, { name: "creative", active: true }];
    assert.equal(activeName(rows), "creative");
});

test("activeName() is empty when nothing on this monitor is focused yet", () => {
    assert.equal(activeName([{ name: "code", active: false }]), "");
    assert.equal(activeName([]), "");
    assert.equal(activeName(undefined), "");
});
