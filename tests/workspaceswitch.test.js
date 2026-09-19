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
    rowState, selector, buildRows, filterRows, roleForScreen, activeName,
    attachLive
} = loadLibrary("modules/bar/WorkspaceSwitch.js", [
    "catalogOrder", "modeOrder", "iconFor", "orderBy", "canonical",
    "barWorkspaces", "rowState", "selector", "buildRows", "filterRows",
    "roleForScreen", "activeName", "attachLive"
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

test("barWorkspaces() synthesizes a zero-window row for an admitted scene Hyprland has not created yet (LEO-373)", () => {
    // "code" holds no live workspace at all here — the mode still admits it,
    // so the bar must still show it, dormant, at its declared position.
    const rows = barWorkspaces(declaration, "work", "primary", []);
    assert.deepEqual(rows, [{ id: null, name: "code", occupied: false }]);
});

test("barWorkspaces() mixes a synthesized admitted row with a real occupied one, in declared order", () => {
    const rows = barWorkspaces(declaration, "work", "secondary", [
        { id: 9, name: "media", occupied: true }
    ]);
    assert.deepEqual(rows, [{ id: 9, name: "media", occupied: true }]);

    // Two admitted scenes on one role: one real+empty, one not created yet.
    const twoScene = {
        base: declaration.base,
        modes: { work: { scenes: [
            { name: "code", monitor: "primary" },
            { name: "creative", monitor: "primary" }
        ] } }
    };
    const mixed = barWorkspaces(twoScene, "work", "primary", [
        { id: 4, name: "code", occupied: false }
    ]);
    assert.deepEqual(mixed, [
        { id: 4, name: "code", occupied: false },
        { id: null, name: "creative", occupied: false }
    ]);
});

test("rowState() is focused when active, else playing with a window and dormant without", () => {
    assert.equal(rowState({ occupied: true, active: true }), "focused");
    assert.equal(rowState({ occupied: false, active: true }), "focused");
    assert.equal(rowState({ occupied: true, active: false }), "playing");
    assert.equal(rowState({ occupied: false, active: false }), "dormant");
});

test("rowState() treats a synthesized not-yet-created row as dormant", () => {
    assert.equal(rowState({ id: null, name: "code", occupied: false }), "dormant");
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

test("roleForScreen() reads the geometry store's published role map", () => {
    const roles = { primary: "DP-1", secondary: "DP-2" };
    assert.equal(roleForScreen(roles, "DP-1"), "primary");
    assert.equal(roleForScreen(roles, "DP-2"), "secondary");
});

test("roleForScreen() calls an unrecognised screen secondary, never guesses from key order", () => {
    assert.equal(roleForScreen({ primary: "DP-1" }, "HDMI-A-1"), "secondary");
});

test("roleForScreen() reads every screen as primary until the store carries a role map (pre-LEO-368)", () => {
    assert.equal(roleForScreen({}, "eDP-1"), "primary");
    assert.equal(roleForScreen(undefined, "eDP-1"), "primary");
});

test("roleForScreen() never calls the secondary output primary, even as the map's only entry", () => {
    assert.equal(roleForScreen({ secondary: "HDMI-A-1" }, "HDMI-A-1"), "secondary");
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

// LEO-344: three admitted scenes (code, obsidian-linear, proton) all live on
// this Hyprland build with `id: -1` — it reports no numeric identity for a
// named workspace at all, rather than a merely unstable one. Matching by id
// collapsed all three onto whichever workspace a same-keyed map inserted
// last, duplicating it across the other two rows.
test("attachLive() matches rows to their live workspace by name, not id", () => {
    const rows = [
        { id: -1, name: "code", occupied: true },
        { id: -1, name: "obsidian-linear", occupied: true },
        { id: -1, name: "proton", occupied: true }
    ];
    const live = [
        { id: -1, name: "code", active: true },
        { id: -1, name: "obsidian-linear", active: false },
        { id: -1, name: "proton", active: false }
    ];
    assert.deepEqual(attachLive(rows, live), live);
});

test("attachLive() passes a synthesized row (id: null) through unmatched", () => {
    const rows = [{ id: null, name: "logs", occupied: false }];
    assert.deepEqual(attachLive(rows, []), rows);
});

// LEO-337 follow-up: on this Hyprland build, every workspace's own
// `active`/`focused` flag (Quickshell's id-keyed tracking) was observed live
// to update only on a monitor-crossing focus change, not a plain
// same-monitor workspace switch — so the bar's active pill never moved
// between mod+h/l crossings. `activeWsName` is the monitor's own
// `activeWorkspace.name`, confirmed correct live by `hyprctl -j monitors`,
// and updates on every switch. Passing it makes activeName() ignore each
// row's stale `active` flag entirely and match by name instead.
test("activeName(rows, activeWsName) matches by name, ignoring a stale per-row active flag", () => {
    const rows = [
        { name: "code", active: true },   // stale: this build's Hyprland
        { name: "proton", active: false } // no longer flags focus correctly.
    ];
    assert.equal(activeName(rows, "proton"), "proton");
});

test("activeName(rows, activeWsName) is empty when the active workspace isn't one of this monitor's rows", () => {
    const rows = [{ name: "code", active: false }];
    assert.equal(activeName(rows, "logs"), "");
});

test("activeName(rows, activeWsName) is empty when no monitor focus is known yet", () => {
    assert.equal(activeName([{ name: "code", active: true }], ""), "");
});

// The user's second, unrelated report: scene order must always follow the
// mode's declared list — never re-sorted by liveness, occupancy, or Hyprland's
// own creation order. Use a 3-scene fixture (the 2-scene one above can't
// distinguish "declared order" from "coincidence").
const threeScene = {
    base: { scenes: { code: {}, obsidian: {}, proton: {} } },
    modes: {
        work: {
            scenes: [
                { name: "code", monitor: "primary" },
                { name: "obsidian", monitor: "primary" },
                { name: "proton", monitor: "primary" }
            ]
        }
    }
};

test("barWorkspaces() orders admitted rows by the declared scene list, regardless of the live list's order", () => {
    const declaredOrder = ["code", "obsidian", "proton"];
    // Every permutation of arrival order, occupancy, and id assignment that
    // Hyprland's creation order or liveness could plausibly produce.
    const arrivalPermutations = [
        [{ id: 3, name: "proton", occupied: true }, { id: 1, name: "code", occupied: false }, { id: 2, name: "obsidian", occupied: true }],
        [{ id: 1, name: "code", occupied: true }, { id: 2, name: "obsidian", occupied: true }, { id: 3, name: "proton", occupied: true }],
        [{ id: 9, name: "obsidian", occupied: false }, { id: 7, name: "proton", occupied: false }, { id: 5, name: "code", occupied: false }],
        [] // nothing live yet — every row synthesized
    ];
    for (const live of arrivalPermutations) {
        const rows = barWorkspaces(threeScene, "work", "primary", live);
        assert.deepEqual(rows.map(r => r.name), declaredOrder);
    }
});

test("attachLive() preserves barWorkspaces()' row order (matches in place, never resorts)", () => {
    const rows = barWorkspaces(threeScene, "work", "primary", [
        { id: -1, name: "code", occupied: true },
        { id: -1, name: "obsidian", occupied: true },
        { id: -1, name: "proton", occupied: true }
    ]);
    // Live objects arrive in a different (Hyprland creation/event) order.
    const live = [
        { id: -1, name: "proton", active: true },
        { id: -1, name: "code", active: false },
        { id: -1, name: "obsidian", active: false }
    ];
    const attached = attachLive(rows, live);
    assert.deepEqual(attached.map(r => r.name), ["code", "obsidian", "proton"]);
});
