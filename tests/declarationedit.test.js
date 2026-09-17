// The mode panel's edit half (LEO-280).
//
// A declaration is edited from the shell, validated before the write. The
// panel is the second runtime; the compositor resolves from the same store —
// so a refused write is the difference between a typo and a desk that
// materialises wrong.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { validId, validPalette, presentation, modePatch } = loadLibrary("services/DeclarationEdit.js");

test("ids read like the schema's $defs/id", () => {
    assert.ok(validId("macchiato"));
    assert.ok(validId("gruvbox-material"));
    assert.ok(!validId("Macchiato"), "case cannot split one sender in two");
    assert.ok(!validId(""), "");
    assert.ok(!validId("-4parse"), "a leading dash is not an id");
    assert.ok(!validId("has spaces"));
});

test("a lease edit rides the whole presentation value", () => {
    const next = presentation(
        { palette: "latte" },
        { palette: "mocha" },
    );
    assert.deepEqual(next, { palette: "mocha" });
});

test("a lease may be vacated, and that reads as no lease", () => {
    const next = presentation({ palette: "latte" }, { palette: "" });
    assert.equal(next.palette, "");
});

test("an id that is not an id is refused, not stored", () => {
    assert.equal(presentation({}, { palette: "Catppuccin Mocha" }), null);
});

test("a day/night pair with both halves valid ids is accepted", () => {
    const next = presentation({}, { palette: { day: "latte", night: "mocha" } });
    assert.deepEqual(next.palette, { day: "latte", night: "mocha" });
});

test("a pair with an invalid half is refused, not stored", () => {
    assert.equal(presentation({}, { palette: { day: "Latte", night: "mocha" } }), null);
    assert.equal(presentation({}, { palette: { day: "latte" } }), null);
});

test("validPalette accepts the vacated, plain-id and pair forms", () => {
    assert.ok(validPalette(""));
    assert.ok(validPalette("mocha"));
    assert.ok(validPalette({ day: "latte", night: "mocha" }));
    assert.ok(!validPalette({ day: "latte" }));
    assert.ok(!validPalette({ day: "Latte", night: "mocha" }));
});

test("the patch stays whole-field: rendered values, not fragments", () => {
    const next = modePatch(
        { name: "Gaming", presentation: { palette: "latte" } },
        { palette: "" },
    );
    assert.deepEqual(next, { name: "Gaming", presentation: { palette: "" } });
});

test("a refused contract edit answers not a partial write", () => {
    assert.equal(modePatch({}, { palette: "NO" }), null);
});

test("a mode-spec-less edit still builds a whole presentation", () => {
    const next = modePatch(null, { palette: "latte" });
    assert.deepEqual(next, { presentation: { palette: "latte" } });
});
