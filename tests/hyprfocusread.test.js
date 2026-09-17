// Reading a declaration without resolving one.
//
// The line this holds is the important part: resolution exists in Lua and in
// Python already, and a third implementation that disagreed with either about
// what a mode means would reintroduce exactly the divergence the design
// removes. So these tests pin what the shell reports *and* what it declines to.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadLibrary } from "./qml.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const { label, ids, known, withholds, narrows, scenes } = loadLibrary("services/HyprfocusRead.js");
const shipped = JSON.parse(readFileSync(join(root, "assets/hyprfocus.default.json"), "utf8"));

test("names a mode from the declaration", () => {
    assert.equal(label(shipped, "work"), "Work");
});

test("falls back to the id so an unknown mode is still named", () => {
    // A pointer naming a mode the declaration lost is a real state; rendering
    // a blank would look like nothing is on.
    assert.equal(label(shipped, "ghost"), "ghost");
    assert.equal(known(shipped, "ghost"), false);
});

test("lists every user-facing mode, sorted, without the hidden fallback", () => {
    // neutral is the recovery fallback reached from a submap; offering it as
    // a peer of the real modes would make it a choice rather than a floor.
    assert.deepEqual(ids(shipped), ["gaming", "study", "work"]);
    assert.equal(known(shipped, "neutral"), true, "hidden is not undeclared");
});

test("excludes any mode flagged hidden, not just neutral by name", () => {
    // The picker contract is the flag, not the id: a second hidden mode must
    // vanish from the list exactly like neutral does, and un-hiding neutral
    // (hypothetically) must bring it back.
    const declaration = {
        modes: {
            neutral: { name: "Neutral", hidden: true },
            work: { name: "Work" },
            ghost: { name: "Ghost Mode", hidden: true },
        },
    };
    assert.deepEqual(ids(declaration), ["work"]);

    const unhidden = { modes: { neutral: { name: "Neutral" }, work: { name: "Work" } } };
    assert.deepEqual(ids(unhidden), ["neutral", "work"]);
});

test("reads a mode's scene set with its monitor roles", () => {
    assert.deepEqual(scenes(shipped, "study"), [
        { name: "code", monitor: "primary" },
        { name: "obsidian-linear", monitor: "secondary" },
        { name: "proton", monitor: "primary" },
    ]);
    assert.deepEqual(scenes(shipped, "ghost"), []);
});

test("survives a declaration that is not there yet", () => {
    // The store is seeded by the CLI, so the shell can start before one exists.
    assert.deepEqual(ids(undefined), []);
    assert.deepEqual(withholds(null, "gaming"), []);
    assert.equal(known({}, "gaming"), false);
});

test("names what a mode explicitly removes", () => {
    const gone = withholds(shipped, "work");
    assert.ok(gone.includes("dofus"), "a withheld binding tree");
    // Named rather than implied: `remove` says the same as an empty `only`
    // here, and only one of them can be reported back to the user.
});

test("the resting mode still withholds the gaming tree", () => {
    // Neutral is not "everything on". The Dofus submap is meaningful while a
    // Dofus group is on screen and noise otherwise, which is the whole reason
    // binding trees are conditional. The gaming shelves now travel with their
    // owning scenes (dofus, steam-games) rather than base.bindings, so they
    // are no longer a withheld base tree here.
    assert.deepEqual(withholds(shipped, "neutral"), ["dofus"]);
});

test("gaming is the mode that keeps the conditional trees", () => {
    // It still withholds background work — keeping the Dofus binds and
    // stopping the sync are the same mode saying two different things.
    const gone = withholds(shipped, "gaming");
    assert.ok(!gone.includes("dofus"), "game withheld the tree it exists to provide");
    assert.ok(gone.includes("linear-sync"), "gaming should still stop the sync");
});

test("does not guess at what an exclusive set leaves out", () => {
    // A scene set is exclusive: `code` is absent from gaming without any
    // `remove` naming it. Withholds reports deltas only, never the scenes a
    // set leaves out; `narrows` flags an `only` delta when one is written.
    assert.deepEqual(withholds(shipped, "gaming").filter(n => n === "code"), []);
    assert.equal(narrows({ modes: { m: { services: { only: [] } } } }, "m"), true);
});

test("a mode using only removals is reported in full", () => {
    assert.equal(narrows(shipped, "work"), false);
});

test("merges a mode's notification routes over the base's", () => {
    const { routes } = loadLibrary("services/HyprfocusRead.js");
    const game = routes(shipped, "gaming");
    assert.equal(game.default, "drop", "the mode's fallback wins");
});

test("keeps a base rule the mode does not mention", () => {
    const { routes } = loadLibrary("services/HyprfocusRead.js");
    const declaration = {
        base: { notify: { default: "show", "linear-sync": "queue" } },
        modes: { gaming: { name: "Gaming", notify: { default: "drop" } } }
    };
    assert.deepEqual(routes(declaration, "gaming"), { default: "drop", "linear-sync": "queue" });
});

test("reports no routing rather than a guess when nothing is declared", () => {
    // An empty table reads as "nothing declared"; inventing a default here
    // would silence notifications the moment the store went missing.
    const { routes } = loadLibrary("services/HyprfocusRead.js");
    assert.deepEqual(routes(undefined, "gaming"), {});
});
