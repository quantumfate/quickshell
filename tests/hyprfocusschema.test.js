// The shipped declaration against its own schema.
//
// `schemas/hyprfocus.schema.json` is the contract for the store `,hyprfocus
// seed` installs, and it had silently drifted: scenes declare `layout`,
// `columns` and `docks`, the schema knew none of them, and the scene object
// is `additionalProperties: false` — so the file this repo ships would have
// failed its own schema, unnoticed, because nothing ever checked.
//
// The validator below is a deliberate subset of JSON Schema — enough for the
// keywords these schemas actually use — rather than a dependency: this repo's
// tests run on `node --test` with no node_modules, and a schema gate that
// needs an install is a gate that gets skipped.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const schema = JSON.parse(readFileSync(join(root, "schemas/hyprfocus.schema.json"), "utf8"));
const declaration = JSON.parse(readFileSync(join(root, "assets/hyprfocus.default.json"), "utf8"));

/** Resolve a local `#/$defs/x` reference against the root schema. */
function deref(node) {
    let seen = 0;
    while (node && node.$ref) {
        assert.ok(node.$ref.startsWith("#/"), `only local refs are supported: ${node.$ref}`);
        assert.ok(++seen < 20, `circular $ref chain at ${node.$ref}`);
        node = node.$ref
            .slice(2)
            .split("/")
            .reduce((acc, key) => acc?.[key.replace(/~1/g, "/").replace(/~0/g, "~")], schema);
    }
    return node;
}

function typeOf(value) {
    if (value === null) return "null";
    if (Array.isArray(value)) return "array";
    if (Number.isInteger(value)) return "integer";
    return typeof value === "number" ? "number" : typeof value;
}

function typeMatches(want, value) {
    const actual = typeOf(value);
    if (want === "number") return actual === "number" || actual === "integer";
    return want === actual;
}

/**
 * Validate `value` against `node`, collecting human-readable failures.
 * @returns {string[]} one line per violation, empty when it validates
 */
function validate(value, node, path = "") {
    node = deref(node);
    if (!node || node === true) return [];
    const out = [];
    const where = path || "(root)";

    if ("const" in node && value !== node.const) {
        out.push(`${where}: expected ${JSON.stringify(node.const)}, got ${JSON.stringify(value)}`);
    }
    if (node.enum && !node.enum.includes(value)) {
        out.push(`${where}: ${JSON.stringify(value)} is not one of ${node.enum.join(", ")}`);
    }
    if (node.type) {
        const types = Array.isArray(node.type) ? node.type : [node.type];
        if (!types.some(t => typeMatches(t, value))) {
            out.push(`${where}: expected ${types.join("|")}, got ${typeOf(value)}`);
            return out; // every further keyword would pile on the same mistake
        }
    }
    if (node.oneOf) {
        const passing = node.oneOf.filter(branch => validate(value, branch, path).length === 0);
        if (passing.length !== 1) {
            out.push(`${where}: matched ${passing.length} of ${node.oneOf.length} oneOf branches`);
        }
    }

    const kind = typeOf(value);
    if (kind === "string") {
        if (node.pattern && !new RegExp(node.pattern).test(value)) {
            out.push(`${where}: ${JSON.stringify(value)} does not match ${node.pattern}`);
        }
        if (node.maxLength !== undefined && [...value].length > node.maxLength) {
            out.push(`${where}: longer than ${node.maxLength}`);
        }
    }
    if (kind === "number" || kind === "integer") {
        if (node.minimum !== undefined && value < node.minimum) out.push(`${where}: below ${node.minimum}`);
        if (node.maximum !== undefined && value > node.maximum) out.push(`${where}: above ${node.maximum}`);
        if (node.exclusiveMinimum !== undefined && value <= node.exclusiveMinimum) {
            out.push(`${where}: not above ${node.exclusiveMinimum}`);
        }
    }
    if (kind === "array") {
        if (node.minItems !== undefined && value.length < node.minItems) out.push(`${where}: fewer than ${node.minItems} items`);
        if (node.maxItems !== undefined && value.length > node.maxItems) out.push(`${where}: more than ${node.maxItems} items`);
        if (node.uniqueItems) {
            const seen = new Set(value.map(v => JSON.stringify(v)));
            if (seen.size !== value.length) out.push(`${where}: items are not unique`);
        }
        if (node.items) value.forEach((item, i) => out.push(...validate(item, node.items, `${where}[${i}]`)));
    }
    if (kind === "object") {
        for (const key of node.required ?? []) {
            if (!(key in value)) out.push(`${where}: missing required "${key}"`);
        }
        for (const [key, child] of Object.entries(value)) {
            const sub = node.properties?.[key];
            if (sub) {
                out.push(...validate(child, sub, `${where}.${key}`));
            } else if (node.additionalProperties === false) {
                out.push(`${where}: "${key}" is not declared in the schema`);
            } else if (typeof node.additionalProperties === "object") {
                out.push(...validate(child, node.additionalProperties, `${where}.${key}`));
            }
        }
    }
    return out;
}

test("the shipped hyprfocus declaration validates against its own schema", () => {
    const failures = validate(declaration, schema);
    assert.deepEqual(failures, [], `\n  ${failures.join("\n  ")}\n`);
});

test("the validator actually rejects what the schema forbids", () => {
    // A test that only ever passes proves nothing about the validator. These
    // are the three shapes the drift took: an undeclared key on a strict
    // object, a value outside an enum, and a malformed dock target.
    const bad = structuredClone(declaration);
    bad.base.scenes.code.nonsense = true;
    assert.ok(validate(bad, schema).some(f => f.includes("nonsense")), "an undeclared scene key passed");

    const badLayout = structuredClone(declaration);
    badLayout.base.scenes.code.layout = "decks";
    assert.ok(validate(badLayout, schema).some(f => f.includes("layout")), "an unknown layout passed");

    const badDock = structuredClone(declaration);
    badDock.base.scenes.code.docks["bar.clock"] = { at: "top-elsewhere", of: "block:1" };
    assert.ok(validate(badDock, schema).some(f => f.includes("bar.clock")), "a bad anchor passed");
});
