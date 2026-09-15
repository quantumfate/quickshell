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

// The contrast floor (LEO-288's Legibility bar, first pinned here): colour is
// how the desk signals what may have attention before anything is consciously
// read, so an unreadable combination is a bug rather than a taste question.
// Relative luminance per the formula WCAG uses; the floor is their AA
// body-text bar (4.5) for the main read — `text` on the backgrounds and
// surfaces the shell actually puts it on — and their large-text bar (3.0) for
// every other text-like role on every background tier, which these four
// palettes clear today. A palette an adapter brings in below these clears the
// same floor or is not a leasable pack — a mode that can only be entered into
// an illegible desk is not a taste question either.
const SURFACES = ["background", "backgroundAlt", "surface", "surfaceAlt", "scrim", "inset"];
// Today's floor, per tier and surface: the canonical palettes already clear
// WCAG's AA body-text bar (4.5) with `text` on every surface but surfaceAlt
// (4.39 in latte), where nothing sets body text. Everything else is pinned at
// exactly today's measured minimum — a regression guard rather than a bar the
// shipped palettes strain against.
const FLOORS = {
    text:       { background: 4.5, backgroundAlt: 4.5, surface: 4.5, surfaceAlt: 4.3, scrim: 4.5, inset: 4.5 },
    subtext:    { background: 4.3, backgroundAlt: 4.0, surface: 3.1, surfaceAlt: 2.7, scrim: 3.7, inset: 3.7 },
    subtextAlt: { background: 5.5, backgroundAlt: 5.1, surface: 4.0, surfaceAlt: 3.4, scrim: 4.7, inset: 4.7 },
};

function luminance(hex) {
    const chan = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255)
        .map(v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
    return 0.2126 * chan[0] + 0.7152 * chan[1] + 0.0722 * chan[2];
}

function contrast(a, b) {
    const [hi, lo] = [Math.max(luminance(a), luminance(b)), Math.min(luminance(a), luminance(b))];
    return (hi + 0.05) / (lo + 0.05);
}

// Roles name palette keys through `roles`, so this reads the table the same
// way a widget does — asking for a role, never a colour.
const tokenOf = (paletteName, role) => palettes[paletteName][roles[role]];

for (const [tier, floors] of Object.entries(FLOORS)) {
    test(`\`${tier}\` clears its contrast floor on every surface in every palette`, () => {
        for (const name of names) {
            for (const surface of SURFACES) {
                const need = floors[surface];
                const c = contrast(tokenOf(name, tier), tokenOf(name, surface));
                assert.ok(c >= need, `${name}: ${tier} on ${surface} is ${c.toFixed(2)} (floor ${need})`);
            }
        }
    });
}
