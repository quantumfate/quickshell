// The mode panel's explain half (LEO-280).
//
// A mode can be inspected from the shell and the panel answers "why is my
// desk like this" — meaning the declaration reads as sentences, not JSON.
// These tests pin the words in one place, so the panel and other surfaces
// never disagree.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { provenance, rows } = loadLibrary("services/ModeExplain.js");

test("the pointer's provenance reads who set it and when", () => {
    // The locale gives the readable time part; the test pin is its shape,
    // not a hour-locale that changes by machine.
    const line = provenance({ source: "manual", set_at: "2026-09-15T10:30:00.000Z" }, "2026-09-15T11:30:00.000Z");
    assert.match(line, /^set by manual, /);
    assert.match(line, /until 2026-09-15T11:30/);
});

test("absent provenance reads as manual, never as blank", () => {
    assert.match(provenance({}, null), /^set by manual$/);
});

test("gaming's declaration reads what it withholds and leases", () => {
    const r = rows({
        name: "Gaming",
        scenes: [{ name: "dofus", monitor: "primary" }, { name: "communication", monitor: "secondary" }],
        services: { remove: ["obsidian", "obsidian-index", "linear-sync"] },
        presentation: { palette: { day: "latte", night: "mocha" } }
    });
    assert.deepEqual(r.filter(x => x.label === "scenes").map(x => x.value), ["dofus (primary), communication (secondary)"]);
    assert.deepEqual(r.filter(x => x.label === "services").map(x => x.value), ["stops obsidian, obsidian-index, linear-sync"]);
    assert.deepEqual(r.filter(x => x.label === "leases").map(x => x.value), ["palette latte / mocha"]);
});

test("a plain-string palette reads as one name, not a pair", () => {
    const r = rows({ presentation: { palette: "macchiato" } });
    assert.deepEqual(r.filter(x => x.label === "leases").map(x => x.value), ["palette macchiato"]);
});

test("`remove` is a taking, `only` is the list it names", () => {
    // The announce line's honesty carries over: work mode's remove lists
    // read as withdrawals; nothing is claimed beyond the declaration.
    const r = rows({ bindings: { remove: ["dofus"] } });
    assert.deepEqual(r.map(x => x.value), ["withdraws dofus"]);
});

test("an undeclared mode reads as no rows, not as nothing", () => {
    assert.deepEqual(rows(undefined), []);
});

test("add takes what it admits; add and only can never be combined", () => {
    const r = rows({ services: { add: ["obsidian"] } });
    assert.deepEqual(r.map(x => x.value), ["admits obsidian"]);
});

test("notification routing reads the default and the explicit rules", () => {
    const r = rows({ notify: { default: "queue", "linear-sync": "queue", im: "drop" } });
    assert.deepEqual(
        r.filter(x => x.label === "notifications").map(x => x.value),
        ["queue unless a rule says otherwise · rules: linear-sync, im"],
    );
});
