// The which-key tree logic (LEO-222).
//
// hypr/lib/whichkey.lua records every submap.tree node at config load and dumps
// it to $XDG_STATE_HOME/whichkey.json, which WhichKey.qml consumes through a
// Store. This test exercises the pure selector logic on the same JSON shape,
// so a registry change on the Lua side shows up here instead of as a blank
// overlay.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { nodeFor, pathFromRoot, rowsFor } = loadLibrary("modules/whichkey/WhichKey.js");

// Shape mirroring what whichkey.lua dumps (items are registry order).
const TREE = {
    "which": {
        parent: "",
        items: [
            { key: "t", mods: [], desc: "Terminal", group: false },
            { key: "s", mods: [], desc: "Screen capture", group: false },
            {
                key: "d", mods: [], desc: "Dofus", group: true, child: "dofus"
            },
        ],
    },
    "dofus": {
        parent: "which",
        items: [
            { key: "1", mods: [], desc: "Team one", group: false },
            { key: "t", mods: ["ALT"], desc: "Switch team", group: false },
        ],
    },
    "terminal": {
        parent: "which",
        items: [],
    },
};

test("nodeFor resolves the submap being rendered", () => {
    assert.equal(nodeFor(TREE, ""), null);
    assert.equal(nodeFor(TREE, "reset"), null);
    assert.equal(nodeFor(TREE, "which"), TREE.which);
    assert.equal(nodeFor(TREE, "dofus"), TREE.dofus);
    assert.equal(nodeFor(TREE, "nonexistent"), null);
});

test("the empty tree has no node (fresh config, pre-dump)", () => {
    assert.equal(nodeFor({}, "which"), null);
});

test("pathFromRoot walks parents up to the tree root", () => {
    assert.deepEqual(pathFromRoot(TREE, "dofus"), ["which", "dofus"]);
    assert.deepEqual(pathFromRoot(TREE, "which"), ["which"]);
    assert.deepEqual(pathFromRoot(TREE, ""), []);
    // A node missing from the tree still renders under its own name.
    assert.deepEqual(pathFromRoot(TREE, "orphan"), ["orphan"]);
});

test("rowsFor keeps registry order and comoses key combinations", () => {
    const rows = rowsFor(TREE.dofus);
    assert.equal(rows.length, 2);
    assert.deepEqual(rows[0], {
        key: "1", combo: "1", desc: "Team one", group: false, child: "",
    });
    assert.deepEqual(rows[1], {
        key: "t", combo: "ALT+t", desc: "Switch team", group: false, child: "",
    });
});

test("rowsFor flags groups and carries their child submap", () => {
    const rows = rowsFor(TREE.which);
    assert.equal(rows[2].group, true);
    assert.equal(rows[2].child, "dofus");
    assert.equal(rows[2].combo, "d");
});

test("rowsFor tolerates missing or empty nodes and drops undescribed rows", () => {
    assert.deepEqual(rowsFor(undefined), []);
    assert.deepEqual(rowsFor(null), []);
    assert.deepEqual(rowsFor({}), []);
    assert.deepEqual(rowsFor(TREE.terminal), []);
    assert.deepEqual(rowsFor({ items: [
        { key: "x", desc: "" },
        { key: "y", desc: "Keep me" },
        { desc: "No key" },
    ] }), [{ key: "y", combo: "y", desc: "Keep me", group: false, child: "" }]);
});
// The snap chain (LEO-300): appearance dwells, dismissal is instant.
//
// The perceived snap is two numbers: how long until the menu is USABLE while
// dwelling (the render is pure — instant), and how long the lingering tail
// runs after you leave. The former is the fade the mode's motion contract
// names; the latter must be ZERO: `close()` unmaps in the same tick, no
// Timer, no LEO-302-timeout in the chain. Rendered as pure model words the
// QML reads, so the QML has no number left to invent.
const { fadeFor, snapAfterLeave } = loadLibrary("modules/whichkey/WhichKey.js");

test("the entrance read gives an instant mode its instrument: 30ms, base is a dwell", () => {
    assert.equal(fadeFor("instant", 30, 90), 30);
    assert.equal(fadeFor("base", 30, 90), 90);
    assert.equal(fadeFor(undefined, 30, 90), 90, "base is the fallback");
});

test("the lingering tail of a dismissal is zero, by contract", () => {
    // The overlay unmaps in the same tick the submap leaves: a Timer anywhere
    // in this path would both swallow input and break on the dead timer
    // runtime (LEO-302). The model pins the answer so the contract survives.
    assert.equal(snapAfterLeave(), 0);
});
