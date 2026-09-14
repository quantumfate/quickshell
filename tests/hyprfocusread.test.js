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
const { label, ids, known, withholds, narrows } = loadLibrary("services/HyprfocusRead.js");
const shipped = JSON.parse(readFileSync(join(root, "assets/hyprfocus.default.json"), "utf8"));

test("names a mode from the declaration", () => {
    assert.equal(label(shipped, "deep"), "Deep work");
});

test("falls back to the id so an unknown mode is still named", () => {
    // A pointer naming a mode the declaration lost is a real state; rendering
    // a blank would look like nothing is on.
    assert.equal(label(shipped, "ghost"), "ghost");
    assert.equal(known(shipped, "ghost"), false);
});

test("lists every declared mode, sorted", () => {
    assert.deepEqual(ids(shipped), ["chores", "deep", "game", "llm", "media", "neutral", "reflect"]);
});

test("survives a declaration that is not there yet", () => {
    // The store is seeded by the CLI, so the shell can start before one exists.
    assert.deepEqual(ids(undefined), []);
    assert.deepEqual(withholds(null, "game"), []);
    assert.equal(known({}, "game"), false);
});

test("names what a mode explicitly removes", () => {
    const gone = withholds(shipped, "deep");
    assert.ok(gone.includes("gaming"), "a withdrawn workspace");
    assert.ok(gone.includes("dofus"), "a withheld binding tree");
    // Named rather than implied: `remove` says the same as an empty `only`
    // here, and only one of them can be reported back to the user.
});

test("the resting mode still withholds the gaming tree", () => {
    // Neutral is not "everything on". The Dofus submap is meaningful while a
    // Dofus group is on screen and noise otherwise, which is the whole reason
    // binding trees are conditional.
    assert.deepEqual(withholds(shipped, "neutral"), ["dofus"]);
});

test("game is the mode that keeps the conditional trees", () => {
    // It still withholds background work — keeping the Dofus binds and
    // stopping the sync are the same mode saying two different things.
    const gone = withholds(shipped, "game");
    assert.ok(!gone.includes("dofus"), "game withheld the tree it exists to provide");
    assert.ok(gone.includes("linear-sync"), "game should still stop the sync");
});

test("does not guess at what an exclusive set leaves out", () => {
    // `game` names `only` for workspaces. Everything else is withheld just as
    // surely, but knowing that needs the base and the resolver — so this
    // reports what it can see rather than inventing an answer.
    assert.deepEqual(withholds(shipped, "game").filter(n => n === "code"), []);
    assert.equal(narrows(shipped, "game"), true, "and says the answer is partial");
});

test("a mode using only removals is reported in full", () => {
    assert.equal(narrows(shipped, "deep"), false);
});

test("merges a mode's notification routes over the base's", () => {
    const { routes } = loadLibrary("services/HyprfocusRead.js");
    const game = routes(shipped, "game");
    assert.equal(game.default, "drop", "the mode's fallback wins");
});

test("keeps a base rule the mode does not mention", () => {
    const { routes } = loadLibrary("services/HyprfocusRead.js");
    const declaration = {
        base: { notify: { default: "show", "linear-sync": "queue" } },
        modes: { game: { name: "Game", notify: { default: "drop" } } }
    };
    assert.deepEqual(routes(declaration, "game"), { default: "drop", "linear-sync": "queue" });
});

test("reports no routing rather than a guess when nothing is declared", () => {
    // An empty table reads as "nothing declared"; inventing a default here
    // would silence notifications the moment the store went missing.
    const { routes } = loadLibrary("services/HyprfocusRead.js");
    assert.deepEqual(routes(undefined, "game"), {});
});
