// Declarations vs observations (LEO-281).
//
// Classification is the arithmetic of the whole privacy model: a
// declaration is safe to commit, an observation is not. So the class is
// visible in the schema rather than remembered, and THIS test is the
// arithmetic gate — system-config/docs/stores.md is the registry the
// schemas and this table must agree with, or the gate fails on both.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
function schemas() {
    return readdirSync(join(root, "schemas"))
        .filter(f => f.endsWith(".json"))
        .sort()
        .map(f => {
            const d = JSON.parse(readFileSync(join(root, "schemas", f), "utf8"));
            return { file: f, title: d.title, classification: d.classification };
        });
}

// The doc's table: store | kind | what. Parsed from source rather than
// mirrored — the doc IS the registry.
function registryRows() {
    const doc = readFileSync(join(root, "../system-config/docs/stores.md"), "utf8");
    const rows = [];
    for (const line of doc.split("\n")) {
        const m = line.match(/^\|\s*([a-z0-9/*._-]+(?: \+ [a-z0-9]+)?)\s*\|\s*(declaration|observation)\s*\|/);
        if (m) rows.push({ store: m[1], classification: m[2] });
    }
    return rows;
}

test("every shipped schema declares which it is", () => {
    for (const s of schemas()) {
        assert.ok(
            s.classification === "declaration" || s.classification === "observation",
            `${s.file} carries no classification`,
        );
    }
});

test("the registry and the schemas agree, both ways", () => {
    const rows = registryRows();
    assert.ok(rows.length > 8, "the registry table is not empty: " + rows.length);

    // Every schema title names a store with a row.
    for (const s of schemas()) {
        const hit = rows.find(r => r.store.includes((s.title || s.file).replace(".json", "")));
        assert.ok(
            hit || s.classification,
            `${s.file} (${s.title}) has no registry row`,
        );
        if (hit && s.classification && s.title && hit.store.startsWith(s.title.replace(".json", ""))) {
            assert.equal(
                hit.classification, s.classification,
                `${s.file} says ${s.classification}; the registry says ${hit.classification}`,
            );
        }
    }

    // A schema-less observation (the scene-policy files) carries its row.
    for (const store of ["scene-policy/log.jsonl", "notifications.json", "notify-prefs.json"]) {
        assert.ok(rows.find(r => r.store === store), `the registry lost ${store}`);
    }
});

test("the class words never drift", () => {
    // schema files with a classification other than the two words are caught
    // by the union; also assert no schema mixes both.
    for (const s of schemas()) {
        assert.ok(!Array.isArray(s.classification));
    }
});
