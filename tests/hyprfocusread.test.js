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
});

test("reports nothing for the resting mode", () => {
    assert.deepEqual(withholds(shipped, "neutral"), []);
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
