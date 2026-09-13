// focus.json's contract, plus the firm-semantics invariants Focus.qml leans
// on: enforcement reads `mode`/`until` at dispatch time, so a bad shape here
// is a launcher that silently never blocks (or never unblocks).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = p => JSON.parse(readFileSync(join(root, p), "utf8"));

const schema = read("schemas/focus.schema.json");
const defaults = read("assets/focus.default.json");

function validate(doc) {
    const errors = [];
    for (const key of schema.required) if (!(key in doc)) errors.push(`${key} missing`);
    if (schema.properties.mode.enum && !schema.properties.mode.enum.includes(doc.mode)) {
        errors.push(`mode "${doc.mode}" not allowed`);
    }
    if (doc.until !== null && typeof doc.until !== "string") errors.push("until is neither string nor null");
    return errors;
}

test("the shipped defaults satisfy the schema", () => {
    assert.deepEqual(validate(defaults), []);
});

test("defaults start in the unrestricted state", () => {
    assert.equal(defaults.mode, "off");
    assert.equal(defaults.until, null);
});

test("the schema rejects an unknown mode", () => {
    assert.ok(validate({ mode: "paused", until: null }).length);
});

test("Focus.qml's blocked kinds match what the report promises (media, game)", () => {
    const src = readFileSync(join(root, "services/Focus.qml"), "utf8");
    const m = src.match(/blockedKinds:\s*\(\[([^\]]*)\]\)/);
    assert.ok(m, "blockedKinds not found in Focus.qml");
    const kinds = m[1].split(",").map(s => s.trim().replace(/"/g, "")).filter(Boolean);
    assert.deepEqual(kinds.sort(), ["game", "media"]);
});
