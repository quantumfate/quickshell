// The store contract.
//
// theme.json has three readers — the Quickshell Theme singleton, the Hyprland
// opacity rules, and ,theme.sh apply. A field renamed in one place currently
// fails at the third reader, at runtime, on a desk that has already changed
// colour. The schema is the shared definition; these tests hold the schema, the
// shipped defaults and Theme.qml to each other.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadTheme } from "./qml.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = p => JSON.parse(readFileSync(join(root, p), "utf8"));

const schema = read("schemas/theme.schema.json");
const defaults = read("assets/theme.default.json");
const { palettes } = loadTheme();

/** Minimal draft-2020-12 check covering the keywords this schema uses. */
function validate(doc, schema, path = "") {
    const errors = [];
    for (const key of schema.required ?? []) {
        if (!(key in doc)) errors.push(`${path}/${key} is required but missing`);
    }
    if (schema.additionalProperties === false) {
        for (const key of Object.keys(doc)) {
            if (!(key in schema.properties)) errors.push(`${path}/${key} is not in the schema`);
        }
    }
    for (const [key, spec] of Object.entries(schema.properties ?? {})) {
        if (!(key in doc)) continue;
        const value = doc[key];
        const at = `${path}/${key}`;
        if (spec.type === "integer" && !Number.isInteger(value)) errors.push(`${at} is not an integer`);
        else if (spec.type === "number" && typeof value !== "number") errors.push(`${at} is not a number`);
        else if (spec.type === "string" && typeof value !== "string") errors.push(`${at} is not a string`);
        if (spec.enum && !spec.enum.includes(value)) errors.push(`${at} is "${value}", not one of ${spec.enum.join(", ")}`);
        if (spec.minimum !== undefined && value < spec.minimum) errors.push(`${at} is below ${spec.minimum}`);
        if (spec.maximum !== undefined && value > spec.maximum) errors.push(`${at} is above ${spec.maximum}`);
    }
    return errors;
}

test("the shipped defaults satisfy the schema", () => {
    assert.deepEqual(validate(defaults, schema), []);
});

test("the schema rejects what it should", () => {
    assert.ok(validate({ ...defaults, palette: "dracula" }, schema).length, "unknown palette accepted");
    assert.ok(validate({ ...defaults, scale: 9 }, schema).length, "out-of-range scale accepted");
    assert.ok(validate({ ...defaults, mode: "sometimes" }, schema).length, "unknown mode accepted");
    assert.ok(validate({ ...defaults, stray: 1 }, schema).length, "unknown key accepted");
    const { palette, ...missing } = defaults;
    assert.ok(validate(missing, schema).length, "missing required key accepted");
});

test("every palette the schema allows actually exists in Theme.qml", () => {
    for (const name of schema.properties.palette.enum) {
        assert.ok(name in palettes, `schema allows "${name}", Theme.qml has no such palette`);
    }
});

test("every palette in Theme.qml is allowed by the schema", () => {
    // Catches the other direction: adding a palette without widening the enum
    // leaves a value the shell accepts and the schema rejects.
    for (const name of Object.keys(palettes)) {
        assert.ok(
            schema.properties.palette.enum.includes(name),
            `Theme.qml defines "${name}", the schema's enum does not list it`
        );
    }
});

test("the defaults name palettes that exist", () => {
    for (const key of ["palette", "day", "night"]) {
        assert.ok(defaults[key] in palettes, `defaults.${key} = "${defaults[key]}" is not a palette`);
    }
});

test("Theme.qml's own fallbacks agree with the shipped defaults", () => {
    // Theme.qml repeats each default as a `?? fallback`; a file that has never
    // been written must produce the same desk as the shipped one.
    const src = readFileSync(join(root, "services/Theme.qml"), "utf8");
    const fallbacks = Object.fromEntries(
        [...src.matchAll(/store\.get\("(\w+)"\)\s*\?\?\s*("[^"]*"|[\d.]+)/g)]
            .map(m => [m[1], JSON.parse(m[2])])
    );
    for (const [key, value] of Object.entries(fallbacks)) {
        assert.equal(value, defaults[key], `Theme.qml falls back to ${JSON.stringify(value)} for "${key}", defaults say ${JSON.stringify(defaults[key])}`);
    }
});
