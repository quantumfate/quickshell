// The adapter result contract.
//
// `,theme.sh` writes this file and AdapterResult.qml reads it; nothing else
// enforces that they agree. The fixture below is a REAL document captured from
// a live `,theme.sh apply`, so a change to either side that breaks the shape
// fails here rather than in a widget that silently renders nothing.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const schema = JSON.parse(readFileSync(join(root, "schemas/adapter-result.schema.json"), "utf8"));

// Captured from `,theme.sh apply` on quantum-desktop.
const real = {
    ok: true, ts: 1757764800, adapter: "theme",
    applied: [
        { surface: "kitty", tier: "immediate" },
        { surface: "gtk", tier: "immediate" },
        { surface: "qt", tier: "immediate" },
        { surface: "hyprland", tier: "immediate" },
        { surface: "btop", tier: "immediate" },
        { surface: "zathura", tier: "immediate" },
        { surface: "rofi", tier: "immediate" },
        { surface: "wlogout", tier: "immediate" },
        { surface: "wallpaper", tier: "immediate" }
    ],
    pending: [{ surface: "zen", tier: "next-launch", reason: "user.js is read once at launch" }],
    failed: []
};

/** Minimal draft-2020-12 check covering the keywords this schema uses. */
function validate(doc, s = schema, path = "") {
    const errors = [];
    for (const key of s.required ?? []) {
        if (!(key in doc)) errors.push(`${path}/${key} is required but missing`);
    }
    if (s.additionalProperties === false) {
        for (const key of Object.keys(doc)) {
            if (!(key in (s.properties ?? {}))) errors.push(`${path}/${key} is not in the schema`);
        }
    }
    for (const [key, spec] of Object.entries(s.properties ?? {})) {
        if (!(key in doc)) continue;
        const value = doc[key];
        const at = `${path}/${key}`;
        if (spec.type === "integer" && !Number.isInteger(value)) errors.push(`${at} is not an integer`);
        if (spec.type === "boolean" && typeof value !== "boolean") errors.push(`${at} is not a boolean`);
        if (spec.type === "string" && typeof value !== "string") errors.push(`${at} is not a string`);
        if (spec.type === "array") {
            if (!Array.isArray(value)) { errors.push(`${at} is not an array`); continue; }
            for (const [i, item] of value.entries()) errors.push(...validate(item, spec.items, `${at}/${i}`));
        }
        if (spec.$ref === "#/$defs/tier" && !schema.$defs.tier.enum.includes(value)) {
            errors.push(`${at} is "${value}", not a known tier`);
        }
        if (spec.minLength !== undefined && typeof value === "string" && value.length < spec.minLength) {
            errors.push(`${at} is shorter than ${spec.minLength}`);
        }
    }
    return errors;
}

test("a real ,theme.sh result satisfies the schema", () => {
    assert.deepEqual(validate(real), []);
});

test("next-login is not a tier", () => {
    // It was removed once the cursor moved to `hyprctl setcursor`. A document
    // still claiming it means something re-introduced a logout requirement.
    assert.deepEqual(schema.$defs.tier.enum, ["immediate", "next-launch"]);
    const stale = { ...real, pending: [{ surface: "cursor", tier: "next-login", reason: "env" }] };
    assert.ok(validate(stale).length, "a next-login tier was accepted");
});

test("the schema rejects what it should", () => {
    assert.ok(validate({ ...real, ok: "yes" }).length, "non-boolean ok accepted");
    assert.ok(validate({ ...real, stray: 1 }).length, "unknown key accepted");
    assert.ok(validate({ ...real, pending: [{ surface: "zen", tier: "next-launch" }] }).length,
        "a pending entry without a reason was accepted — the reason is the actionable half");
    const { ts, ...noTs } = real;
    assert.ok(validate(noTs).length, "missing ts accepted");
});

test("a failure is not silence", () => {
    // A surface that could not be reached must be named with a reason, and must
    // flip ok. Rendering nine successes and hiding one absence is the exact
    // dishonesty this contract exists to prevent.
    const withFailure = {
        ...real, ok: false,
        applied: real.applied.filter(e => e.surface !== "gtk"),
        failed: [{ surface: "gtk", reason: "catppuccin-mocha-mauve not installed" }]
    };
    assert.deepEqual(validate(withFailure), []);
    assert.equal(withFailure.applied.length + withFailure.failed.length, real.applied.length);
});
