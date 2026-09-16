// DofusRoster.qml contract (LEO-234).
//
// The component depends on Hyprland singletons, so this is a source-level lint
// rather than a runtime render: it verifies the isle wires to the right
// services and exposes the required swap controls.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const src = readFileSync(join(root, "modules/bar/DofusRoster.qml"), "utf8");

test("imports the swap service", () => {
    assert.match(src, /DofusSwap/);
});

test("gates visibility on the gaming workspace with Dofus clients", () => {
    assert.match(src, /_onGaming/);
    assert.match(src, /_hasDofus/);
    assert.match(src, /activeWorkspace\?\.name === "gaming"/);
    assert.match(src, /DofusWindows\.windows/);
});

test("renders members in group order from DofusWindows", () => {
    assert.match(src, /Repeater\s*\{[^}]*model:\s*DofusWindows\.windows/s);
});

test("focuses a selected member", () => {
    assert.match(src, /DofusWindows\.focus\(/);
});

test("exposes recalibrate, learn, and start/stop controls", () => {
    assert.match(src, /DofusSwap\.calibrate\(/);
    assert.match(src, /DofusSwap\.learn\(/);
    assert.match(src, /DofusSwap\.toggle\(/);
    assert.match(src, /"recalibrate"/);
    assert.match(src, /"learn"/);
    assert.match(src, /"start"|"stop"/);
});

test("shows a class icon per character", () => {
    assert.match(src, /ClassIcon\s*\{/);
    assert.match(src, /DofusState\.classOf\(/);
});

test("does not attach to a Hyprland group", () => {
    assert.doesNotMatch(src, /Hyprland\.Group/);
    assert.doesNotMatch(src, /grouped\[/);
});

test("is a standalone Surface island", () => {
    assert.match(src, /Surface\s*\{/);
    assert.match(src, /elevation:\s*"island"/);
});
