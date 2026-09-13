// The palette contract.
//
// `Theme.palettes` is four tables written by hand. A key missing from one of
// them is invisible until you switch to that palette and a widget renders a
// transparent colour — at which point the cause is four files away from the
// symptom. These assertions are what make adding a fifth palette safe.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadTheme } from "./qml.js";

const { palettes, roles, fallback } = loadTheme();
const names = Object.keys(palettes);

test("every palette carries the same keys", () => {
    const reference = Object.keys(palettes[fallback]).sort();
    assert.ok(reference.length > 0, "the fallback palette is empty");

    for (const name of names) {
        assert.deepEqual(
            Object.keys(palettes[name]).sort(),
            reference,
            `palette "${name}" does not match "${fallback}"`
        );
    }
});

test("every colour is a full hex triplet", () => {
    for (const [name, palette] of Object.entries(palettes)) {
        for (const [key, value] of Object.entries(palette)) {
            assert.match(value, /^#[0-9a-f]{6}$/i, `${name}.${key} is not a hex colour`);
        }
    }
});

test("every semantic role resolves in every palette", () => {
    assert.ok(Object.keys(roles).length > 0, "no semantic roles found in Theme.qml");

    for (const [role, key] of Object.entries(roles)) {
        for (const name of names) {
            assert.ok(
                key in palettes[name],
                `role "${role}" reads c.${key}, missing from palette "${name}"`
            );
        }
    }
});

test("the fallback palette exists", () => {
    assert.ok(fallback, "Theme.qml has no `palettes[name] ?? palettes.X` fallback");
    assert.ok(fallback in palettes, `fallback palette "${fallback}" is not defined`);
});

test("cycling visits every palette exactly once before repeating", () => {
    // Mirrors the IPC `cycle`: next in insertion order, wrapping.
    const seen = [];
    let current = fallback;
    for (let i = 0; i < names.length; i++) {
        seen.push(current);
        current = names[(names.indexOf(current) + 1) % names.length];
    }
    assert.equal(current, fallback, "cycle does not return to its starting point");
    assert.deepEqual([...seen].sort(), [...names].sort(), "cycle skips or repeats a palette");
});

test("the day and night palettes the theme store names are defined", () => {
    // theme.json's `day`/`night` fields pick from this table; a typo there is a
    // switch that silently does nothing.
    for (const required of ["latte", "macchiato"]) {
        assert.ok(required in palettes, `palette "${required}" is missing`);
    }
});

test("every role the design spec (02-visual-language / tokens.json) names is covered", () => {
    // Regression guard for LEO-218: the spec's semantic tokens map onto these
    // role names (kept stable because other work is already coded against
    // them) rather than the spec's own dotted names.
    for (const required of [
        "info", "pending", "subtextAlt", "accentSecondary", "scrim", "inset"
    ]) {
        assert.ok(required in roles, `role "${required}" missing from Theme.qml`);
    }
});
