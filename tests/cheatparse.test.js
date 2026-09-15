// The cheatsheet rendering model.
//
// Both the full overlay and the passive peek render whatever this returns —
// now from the which-key registry document rather than a `hyprctl binds`
// scan — so a parsing change shows up as a cheat surface quietly listing the
// wrong binds. The rows are what the mode's admission left enabled: a submap
// withheld by the mode has no node, and an `opens` leaf on a withheld tree
// through the dump — the surface simply cannot list what does not work
// (LEO-268's by-construction contract).
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { parseNode, nodeAs, splitColumns, categorize } = loadLibrary("modules/cheatsheet/CheatParse.js");
const ORDER = ["Window", "Workspace", "Menus", "Media", "Utilities", "Dofus", "Shell", "General"];

const reset = {
    parent: "",
    items: [
        { key: "k", mods: ["SUPER"], desc: "Volume up" },
        { key: "slash", mods: ["SUPER"], desc: "Window: close focused" },
        { key: "1", mods: ["SUPER"], desc: "Workspace: Focus code" },
        { key: "1", mods: ["SUPER", "SHIFT"], desc: "Workspace: Move focused to 1" },
        { key: "d", mods: ["SUPER"], desc: "Repeated duplicate entry" },
    ]
};

test("an explicit Category: prefix wins over keyword matching", () => {
    assert.deepEqual(categorize("Scrolling: fit the active column"), {
        cat: "Scrolling",
        label: "fit the active column"
    });
});

test("descriptions bucket by keyword when unprefixed", () => {
    assert.equal(categorize("Volume up").cat, "Media");
    assert.equal(categorize("Close focused window").cat, "Window");
    assert.equal(categorize("Focus workspace 5").cat, "Workspace");
    assert.equal(categorize("Screen capture").cat, "Utilities");
    assert.equal(categorize("Something unknown").cat, "General");
});

test("a trailing ellipsis marks a submenu", () => {
    assert.equal(categorize("Applications…").cat, "Menus");
    assert.equal(categorize("Applications...").cat, "Menus");
});

test("the root node parses into ordered categories", () => {
    const root = {
        parent: "",
        items: [
            { key: "k", mods: ["SUPER"], desc: "Volume up" },
            { key: "slash", mods: ["SUPER"], desc: "Window: close focused" },
            { key: "1", mods: ["SUPER"], desc: "Workspace: Focus code" },
            { key: "1", mods: ["SUPER", "SHIFT"], desc: "Workspace: Move focused to code" },
        ]
    };
    const names = parseNode(root, ORDER).map(c => c.name);
    // ORDER positions win (rank); relative order comes from the list.
    assert.deepEqual(names, ["Window", "Workspace", "Media"]);
});

test("rows sort by combo within their category", () => {
    const reset = { parent: "", items: [
        { key: "k", mods: ["SUPER"], desc: "Volume up" },
        { key: "b", mods: ["SUPER", "SHIFT"], desc: "Volume down" },
    ] };
    const media = parseNode(reset, ORDER).find(c => c.name === "Media");
    assert.deepEqual(media.rows.map(r => r.combo), [
        "SUPER + k",
        "SUPER + SHIFT + b",
    ]);
});

test("a bind without a description is never rendered", () => {
    const node = { parent: "", items: [{ key: "q", mods: ["SUPER"], desc: "" }] };
    assert.deepEqual(parseNode(node, ORDER), []);
});

test("dedup: the same key, combo and label renders once", () => {
    const node = { parent: "", items: [
        { key: "k", mods: ["SUPER"], desc: "Volume up" },
        { key: "k", mods: ["SUPER"], desc: "Volume up" },
    ] };
    const rows = parseNode(node, ORDER).flatMap(c => c.rows);
    assert.equal(rows.length, 1);
});

test("a submap context renders its own node, not the root's", () => {
    const nodes = {
        reset: { parent: "", items: [{ key: "k", mods: ["SUPER"], desc: "Volume up" }] },
        dofus: { parent: "", items: [{ key: "d", mods: ["SUPER"], desc: "Dofus: open team menu", group: true, child: "dofus-team" }] },
    };
    const rows = parseNode(nodeAs(nodes, "dofus"), ORDER).flatMap(c => c.rows.map(r => r.desc));
    assert.deepEqual(rows, ["open team menu"], "the submap's own volunteering");
});

test("a withered subtree keeps the sheet on the root, never blank", () => {
    // A node the dump no longer names (withheld, or a stale submap name)
    // degrades to the root's rows — the sheet cannot show a context it has
    // no truth for, and never goes empty while the desk has described binds.
    const nodes = { reset: { parent: "", items: [{ key: "k", mods: ["SUPER"], desc: "Volume up" }] } };
    const cats = parseNode(nodeAs(nodes, "ghost"), ORDER);
    assert.ok(cats.some(c => c.name === "Media"));
});

test("an empty registry renders nothing, never a wrong row", () => {
    assert.deepEqual(parseNode(nodeAs({}, ""), ORDER), []);
    assert.deepEqual(parseNode(undefined, ORDER), []);
});

test("two columns split evenly", () => {
    const cats = parseNode({ parent: "", items: [] }, ORDER);
    const [l, r] = splitColumns(cats);
    assert.deepEqual(l, []);
    assert.deepEqual(r, []);
});
