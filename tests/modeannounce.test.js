// The announce phase (LEO-242).
//
// A mode transition that takes something away must say what it will take,
// naming the resources and not just the mode — the difference between
// "entering gaming" and "entering gaming, which stops the sync". These tests
// build the announcement from the same shape the declaration carries.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { taken, sentence, announce } = loadLibrary("services/ModeAnnounce.js");

const gaming = {
    name: "Gaming",
    services: { remove: ["obsidian", "obsidian-index", "linear-sync"] },
    bindings: { remove: ["dofus"] },
    scenes: [{ name: "dofus", monitor: "primary" }]
};

test("the announcement names what the mode takes away, not the mode alone", () => {
    const a = announce(gaming, "Gaming");
    assert.equal(a.title, "Gaming");
    assert.match(a.body, /stopping linear-sync/);
    assert.match(a.body, /withdrawing dofus/);
});

test("a transition that takes nothing has nothing to announce", () => {
    // neutral only adds or restyles; entering an additive mode announces
    // nothing and owes no grace window.
    assert.equal(announce({ name: "Neutral", services: { add: ["obsidian"] } }, "Neutral"), null);
    assert.equal(announce({ name: "Neutral" }, "Neutral"), null);
    assert.equal(announce(undefined, "Neutral"), null);
});

test("the verb reads kind: services stop, trees withdraw", () => {
    const list = taken(gaming);
    const sync = list.find(t => t.id === "linear-sync");
    assert.equal(sync.kind, "services");
    assert.equal(sync.verb, "stopping");
    const binds = list.filter(t => t.kind === "bindings");
    assert.deepEqual(binds.map(t => t.id), ["dofus"]);
    // A scene set is not a taking: the announce line names only removals,
    // so the announcement never claims more than the declaration does.
    assert.deepEqual(taken(gaming).filter(t => t.kind === "scenes"), []);
});

test("several kinds read as one line, separated so each is greppable", () => {
    assert.equal(
        sentence(taken({
            services: { remove: ["linear-sync"] },
            bindings: { remove: ["dofus"] }
        })),
        "stopping linear-sync · withdrawing dofus",
    );
});

test("an empty declaration reads in the same shape", () => {
    // lint() over a declaration the store actually holds Must agree.
    assert.deepEqual(taken({}), []);
});
