// projects.json's contract: `path` is a real field now —
// `,proj.sh` reads it at runtime — but it is machine-specific, so the
// shipped seed (assets/projects.default.json) never carries one; schema
// makes it optional rather than required for exactly that reason. These
// tests hold the schema and the shipped defaults to that, and to each
// other, the way store.test.js does for theme.json.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = p => JSON.parse(readFileSync(join(root, p), "utf8"));

const schema = read("schemas/projects.schema.json");
const defaults = read("assets/projects.default.json");
const entrySchema = schema.properties.projects.additionalProperties;

/** Minimal draft-2020-12 check for one project entry. */
function validateEntry(doc, path) {
    const errors = [];
    for (const key of entrySchema.required ?? []) {
        if (!(key in doc)) errors.push(`${path}/${key} is required but missing`);
    }
    for (const key of Object.keys(doc)) {
        if (!(key in entrySchema.properties)) errors.push(`${path}/${key} is not in the schema`);
    }
    for (const [key, spec] of Object.entries(entrySchema.properties)) {
        if (!(key in doc)) continue;
        const value = doc[key];
        const at = `${path}/${key}`;
        if (spec.type === "boolean" && typeof value !== "boolean") errors.push(`${at} is not a boolean`);
        if (spec.type === "integer" && !Number.isInteger(value)) errors.push(`${at} is not an integer`);
        if (spec.type === "array" && !Array.isArray(value)) errors.push(`${at} is not an array`);
        if (spec.type === "array" && Array.isArray(value) && spec.minItems && value.length < spec.minItems) {
            errors.push(`${at} has fewer than ${spec.minItems} items`);
        }
        if (spec.enum && !spec.enum.includes(value)) errors.push(`${at} is "${value}", not one of ${spec.enum.join(", ")}`);
        if (spec.minimum !== undefined && value < spec.minimum) errors.push(`${at} is below ${spec.minimum}`);
        if (spec.maximum !== undefined && value > spec.maximum) errors.push(`${at} is above ${spec.maximum}`);
    }
    return errors;
}

test("the shipped defaults satisfy the schema", () => {
    for (const [name, entry] of Object.entries(defaults.projects)) {
        assert.deepEqual(validateEntry(entry, name), []);
    }
});

test("the shipped seed carries no path — that's machine-specific, filled in by `,proj.sh sync`", () => {
    for (const [name, entry] of Object.entries(defaults.projects)) {
        assert.ok(!("path" in entry), `${name} carries a path; the schema forbids it`);
    }
});

test("the schema rejects what it should", () => {
    assert.ok(validateEntry({ kind: "repo", windows: [], study: true, priority: 0 }, "x").length, "empty windows accepted");
    assert.ok(validateEntry({ kind: "castle", windows: ["nvim"], study: true, priority: 0 }, "x").length, "unknown kind accepted");
    assert.ok(validateEntry({ kind: "repo", windows: ["nvim"], study: "yes", priority: 0 }, "x").length, "non-boolean study accepted");
    assert.ok(validateEntry({ kind: "repo", windows: ["nvim"], study: true, priority: 99 }, "x").length, "out-of-range priority accepted");
    const { kind, ...missing } = defaults.projects[Object.keys(defaults.projects)[0]];
    assert.ok(validateEntry(missing, "x").length, "missing required key accepted");
});

test("at most one shipped default is the study project", () => {
    const studies = Object.values(defaults.projects).filter(p => p.study);
    assert.ok(studies.length <= 1, "more than one default project claims `study`");
});

test("scopes accepts a name-to-command map, and is optional", () => {
    assert.deepEqual(validateEntry({ kind: "repo", windows: ["nvim"], study: false, priority: 0 }, "x"), []);
    assert.deepEqual(
        validateEntry({ kind: "repo", windows: ["nvim"], study: false, priority: 0, scopes: { test: "just test" } }, "x"),
        [],
    );
});
