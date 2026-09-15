// The theme pack contract (LEO-289).
//
// One interchange language, adapters on the outside. A pack is a family, a
// variant is one palette in it, and the derivation turns base24 slots into
// the shell's semantic roles — so widgets read roles and never slots, and a
// second pack is a new file rather than a tour of every surface named
// `catppuccin`.
//
// The Catppuccin pack was built from the canonical tinted-theming/base24
// mapping (schemes/base24/catppuccin-*.yaml), so "Catppuccin round-trips
// through an adapter with no visible change" is testable for real: the
// derived table must equal the hand-written tables in Theme.qml key for key.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadLibrary, loadTheme } from "./qml.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const packOf = file => JSON.parse(readFileSync(join(root, file), "utf8"));
const { palette, accentHue, counterpart, lint } = loadLibrary("services/ThemePacks.js", [
    "palette", "accentHue", "counterpart", "lint", "SLOTS", "RAMP", "ACCENT_ROLES",
]);
const { palettes } = loadTheme();

const catppuccin = packOf("assets/packs/catppuccin.json");
const gruvbox = packOf("assets/packs/gruvbox.json");

test("the shipped packs are well-formed", () => {
    assert.deepEqual(lint(catppuccin), []);
    assert.deepEqual(lint(gruvbox), []);
});

test("a pack that renders two modes identically is not installable", () => {
    // Two accent roles on one slot is the exact failure the lease exists to
    // prevent: the modes would look the same.
    const broken = structuredClone(catppuccin);
    broken.accents.pink = broken.accents.mauve;
    const problems = lint(broken);
    assert.ok(problems.some(p => p.includes("mauve") && p.includes("pink")));
});

test("a variant missing a slot is not installable", () => {
    const broken = structuredClone(catppuccin);
    delete broken.variants.mocha.slots.base11;
    assert.ok(lint(broken).some(p => p.includes("mocha") && p.includes("base11")));
});

test("a ramp may only carry the steps base24's surface slots skip", () => {
    const broken = structuredClone(catppuccin);
    broken.variants.mocha.ramp.pink = "#f5c2e7";
    assert.ok(lint(broken).some(p => p.includes("unknown step pink")));
});

test("a counterpart naming a variant the pack lost is not installable", () => {
    const broken = structuredClone(catppuccin);
    delete broken.variants.latte;
    assert.ok(lint(broken).some(p => p.includes("macchiato") && p.includes("counterpart")));
});

// Round-trip, no visible change: the derivation from the pack must equal the
// hand tables in Theme.qml key for key — the adapter loses nothing, because
// the ramp carries the steps base24's surface slots skip.
const FIT = {
    background: "base", backgroundAlt: "mantle", surface: "surface0",
    surfaceAlt: "surface1", overlay: "overlay0", border: "surface2",
    text: "text", subtext: "subtext0", subtextAlt: "subtext1",
    scrim: "crust", inset: "crust",
    success: "green", warning: "yellow", error: "red", info: "blue",
    pending: "peach", accentSecondary: "teal", accentAlt: "lavender",
    lavender: "lavender", blue: "blue", peach: "peach",
    green: "green", pink: "pink", teal: "teal", mauve: "mauve"
};

for (const flavour of ["frappe", "macchiato", "mocha", "latte"]) {
    test(`catppuccin ${flavour} round-trips the adapter with no visible change`, () => {
        const derived = palette(catppuccin, flavour);
        assert.ok(derived, `${flavour} derives from the pack`);
        for (const [role, key] of Object.entries(FIT)) {
            assert.equal(
                derived[role]?.toLowerCase(),
                palettes[flavour][key].toLowerCase(),
                `${flavour}: derived ${role} differs from the shipped palette's ${key}`,
            );
        }
    });
}

test("the resolution chain never leaves a desk without a palette", () => {
    // A variant names its own light counterpart (Catppuccin's three darks
    // share latte); a pack with no light variant hands the variant already
    // in hand back, not an error.
    for (const dark of ["frappe", "macchiato", "mocha"]) {
        assert.equal(counterpart(catppuccin, dark, "light"), "latte");
        assert.equal(counterpart(catppuccin, dark, "dark"), dark, "wanting the kind held gives it back");
    }
    // Gruvbox carries one kind only; the cycle takes what is there.
    assert.equal(counterpart(gruvbox, "dark", "light"), "dark");
    assert.equal(counterpart(gruvbox, "dark", "dark"), "dark");
    assert.equal(counterpart(gruvbox, "ghost", "light"), null, "unknown variant answers nothing, not a guess");
});

test("a second pack is a file, not a shell change", () => {
    // Gruvbox arrives straight from the same upstream repo the Catppuccin
    // pack came from; the derivation reads its slots and answers every role
    // the shell can lease, with the seven accents distinct.
    const table = palette(gruvbox, "dark");
    assert.ok(table, "gruvbox derives");
    for (const role of ["background", "backgroundAlt", "surface", "surfaceAlt", "overlay", "border", "text", "subtext", "subtextAlt", "scrim", "inset"]) {
        assert.match(table[role], /^#[0-9a-f]{6}$/i, `${role} resolves`);
    }
    const hues = ["lavender", "blue", "peach", "mauve", "green", "pink", "teal"]
        .map(r => accentHue(gruvbox, "dark", r));
    assert.equal(new Set(hues).size, 7, "all seven mode accents stay distinguishable");
});

test("an unknown accent role reads as mauve, never as a crash", () => {
    assert.equal(accentHue(catppuccin, "mocha", "nonsense"), accentHue(catppuccin, "mocha", "mauve"));
});
