// The which-key tree logic (LEO-222 / LEO-300).
//
// hypr/lib/whichkey.lua records every submap.tree node at config load and dumps
// it to $XDG_STATE_HOME/whichkey.json, which WhichKey.qml consumes through a
// Store. This test exercises the pure selector logic on the same JSON shape,
// so a registry change on the Lua side shows up here instead of as a blank
// overlay.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { nodeFor, pathFromRoot, rowsFor, fadeFor, snapAfterLeave, initialSession, reduceSession } =
    loadLibrary("modules/whichkey/WhichKey.js");

/** Folds an event sequence through reduceSession from a fresh session. */
function run(events) {
    return events.reduce(reduceSession, initialSession());
}

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
        parent: "",
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
        key: "t", combo: "alt+t", desc: "Switch team", group: false, child: "",
    }, "the label reads the glyph set the keyboard shows");
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

// The snap chain (LEO-300): the overlay tracks the submap stack at keyboard
// speed. An instant motion mode gets zero entrance/exit fade so the menu
// appears and disappears with the key; base keeps a gentle fade. In both cases
// the lingering tail after leaving the submap is zero: `close()` unmaps in the
// same tick, no Timer, no LEO-302-timeout in the chain.

test("instant motion energy snaps the overlay to zero fade", () => {
    assert.equal(fadeFor("instant", 30, 90), 0, "instant means no animation");
    assert.equal(fadeFor("base", 30, 90), 90, "base keeps a readable dwell");
    assert.equal(fadeFor(undefined, 30, 90), 90, "base is the fallback");
});

test("the lingering tail of a dismissal is zero, by contract", () => {
    // The overlay unmaps in the same tick the submap leaves: a Timer anywhere
    // in this path would both swallow input and break on the dead timer
    // runtime (LEO-302). The model pins the answer so the contract survives.
    assert.equal(snapAfterLeave(), 0);
});

// reduceSession: the LEO-300 timing/decision state machine, exercised as event
// sequences rather than isolated calls, since the bug was about the CHAIN of
// events (enter -> dwell -> leaf exit), not any single transition.

test("entering a submap arms the dwell instead of opening immediately", () => {
    const s = run([{ type: "submap", data: "which" }]);
    assert.deepEqual(s, { submap: "which", shown: false, dwellArmed: true });
});

test("the dwell firing is what opens the overlay", () => {
    const s = run([{ type: "submap", data: "which" }, { type: "dwellFired" }]);
    assert.deepEqual(s, { submap: "which", shown: true, dwellArmed: false });
});

test("moving to a child submap while already shown follows without re-arming", () => {
    const s = run([
        { type: "submap", data: "which" },
        { type: "dwellFired" },
        { type: "submap", data: "dofus" },
    ]);
    assert.deepEqual(s, { submap: "dofus", shown: true, dwellArmed: false });
});

test("a leaf action's exit (submap back to reset) dismisses with no dwell", () => {
    const s = run([
        { type: "submap", data: "which" },
        { type: "dwellFired" },
        { type: "submap", data: "dofus" },
        { type: "submap", data: "reset" },
    ]);
    assert.deepEqual(s, { submap: "reset", shown: false, dwellArmed: false });
});

test("leaving before the dwell fires cancels it — no open-then-immediately-close flash", () => {
    const s = run([{ type: "submap", data: "which" }, { type: "submap", data: "reset" }]);
    assert.deepEqual(s, { submap: "reset", shown: false, dwellArmed: false });
});

test("explicit dismiss wins over a pending dwell, regardless of the submap event ordering", () => {
    // The issue calls out that a leaf action's dispatch can race the submap
    // event resolving; the explicit `dismiss` IPC must close (and disarm the
    // dwell) whichever of the two lands first.
    const s = run([{ type: "submap", data: "which" }, { type: "dismiss" }]);
    assert.deepEqual(s, { submap: "which", shown: false, dwellArmed: false });
});

test("REGRESSION: a leaf exit never leaves the previous node shown", () => {
    // Full chain: dwell into a nested node, then exit via a leaf action. At
    // every point after the exit event, the overlay must read as hidden and
    // must never claim to still be showing the node that was left.
    const before = run([
        { type: "submap", data: "which" },
        { type: "dwellFired" },
        { type: "submap", data: "dofus" },
        { type: "dwellFired" }, // a second dwell must not have been armed; a no-op if it fires
    ]);
    assert.equal(before.shown, true);
    assert.equal(before.submap, "dofus");

    const afterLeafExit = reduceSession(before, { type: "submap", data: "reset" });
    assert.equal(afterLeafExit.shown, false, "the overlay must be hidden immediately on exit");
    assert.notEqual(afterLeafExit.submap, "dofus", "must not still name the node that was left");

    // A stale dwell timer racing the exit (defensive: QML also stops it
    // synchronously) must not resurrect the overlay on the departed node.
    const staleDwell = reduceSession(afterLeafExit, { type: "dwellFired" });
    assert.equal(staleDwell.shown, false, "a stale dwell must never reopen a departed node");
});
