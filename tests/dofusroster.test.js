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
const button = readFileSync(join(root, "modules/bar/DofusRosterButton.qml"), "utf8");
const windows = readFileSync(join(root, "services/DofusWindows.qml"), "utf8");

test("imports the swap service", () => {
    assert.match(src, /DofusSwap/);
});

test("gates visibility on the dofus workspace with Dofus clients", () => {
    assert.match(src, /_onDofus/);
    assert.match(src, /_members/);
    assert.match(src, /activeWorkspace\?\.name === "dofus"/);
    assert.match(src, /DofusWindows\.windows/);
});

// A client's workspace object is { address, type, name } — no `id`. Joining on
// one made the presence test false for every window, so the isle never showed.
// Both halves of that join are pinned here: the model must publish the name,
// and the isle must compare against it.
test("joins presence on the workspace name, never an id", () => {
    assert.doesNotMatch(src, /workspaceId/);
    assert.match(windows, /workspaceName:\s*c\?\.workspace\?\.name/);
    assert.doesNotMatch(windows, /c\?\.workspace\?\.id/);
});

test("renders members in group order from DofusWindows", () => {
    assert.match(src, /_members:.*DofusWindows\.windows/s);
    assert.match(src, /Repeater\s*\{[^}]*model:\s*root\._members/s);
});

// A mode that does not admit the dofus workspace parks every client on a hold
// workspace. DofusWindows lists a client wherever it stands, so the strip must
// filter, or it offers rows that focus a window the desk has put away.
test("speaks only for clients on the workspace it is drawn over", () => {
    assert.match(src, /w\.workspaceName === root\._mon\?\.activeWorkspace\?\.name/);
    assert.match(src, /visible:\s*root\._onDofus && root\._members\.length > 0/);
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
    // The emblem moved inside the control (one hit target per member), so the
    // roster names the class and the button is what draws it.
    assert.match(src, /iconCls:\s*chipRow\.cls/);
    assert.match(src, /DofusState\.classOf\(/);
    assert.match(button, /ClassIcon\s*\{/);
});

// The dofus workspace hides Hyprland's groupbar, so this strip is the only
// thing on screen naming the focused client. Every member is a real control
// and the focused one is the toggled one.
test("every member is a control, and the focused member is marked", () => {
    assert.match(src, /DofusRosterButton\s*\{[^}]*toggled:\s*chipRow\.active/s);
    assert.match(src, /readonly property bool active: chipRow\.modelData\.focused/);
    assert.doesNotMatch(src, /MouseArea\s*\{/);
});

test("says which characters have a learned turn hash", () => {
    assert.match(src, /DofusSwap\.learned\(/);
    assert.match(src, /marked:\s*chipRow\.learned/);
    assert.match(button, /property bool marked/);
});

test("does not attach to a Hyprland group", () => {
    assert.doesNotMatch(src, /Hyprland\.Group/);
    assert.doesNotMatch(src, /grouped\[/);
});

test("is a standalone Surface island", () => {
    assert.match(src, /Surface\s*\{/);
    assert.match(src, /elevation:\s*"island"/);
});
