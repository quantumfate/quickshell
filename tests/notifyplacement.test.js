// Toast placement (LEO-424): the mood names a position, NotifyPlacement.js
// resolves it to the two anchors the toast surface needs. The resolver is
// loaded from the real source so a schema/asset edit is covered here, and the
// fallback is pinned because an unknown store value must never park the stack
// at a null anchor.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const placement = loadLibrary("services/NotifyPlacement.js", ["resolve", "known", "names", "POSITIONS", "DEFAULT"]);

test("top-centre is the default the mood policy ships", () => {
    assert.equal(placement.DEFAULT, "top-center");
    assert.deepEqual(placement.resolve("top-center"), { v: "top", h: "center" });
});

test("every named position resolves to an edge and an alignment", () => {
    for (const name of placement.names()) {
        const p = placement.resolve(name);
        assert.ok(["top", "bottom"].includes(p.v), `${name} has no vertical edge`);
        assert.ok(["left", "center", "right"].includes(p.h), `${name} has no horizontal alignment`);
    }
});

test("an unknown position falls back instead of anchoring nowhere", () => {
    assert.deepEqual(placement.resolve("middle-ish"), placement.resolve(placement.DEFAULT));
    assert.deepEqual(placement.resolve(undefined), placement.resolve(placement.DEFAULT));
    assert.equal(placement.known("middle-ish"), false);
    assert.equal(placement.known("bottom-right"), true);
});
