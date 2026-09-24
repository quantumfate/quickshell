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
const bar = readFileSync(join(root, "modules/bar/Bar.qml"), "utf8");

test("imports the swap service", () => {
    assert.match(src, /DofusSwap/);
});

test("gates visibility on the dofus workspace with Dofus clients", () => {
    assert.match(src, /_onDofus/);
    assert.match(src, /_members/);
    assert.match(src, /_onDofus: root\._wsName === "dofus"/);
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
    assert.match(src, /w\.workspaceName === root\._wsName/);
    assert.match(src, /shouldShow: root\._onDofus && root\._members\.length > 0/);
});

// `_mon.activeWorkspace` reads stale on a same-monitor switch (Workspaces.qml's
// `_activeWsName` header root-causes it), and a same-monitor switch onto the
// dofus workspace is how this isle is reached — so the name must come from the
// bar's raw-event map, with the cached reference only as the pre-event seed.
test("takes the active workspace from the bar's raw-event map, not the cached monitor", () => {
    assert.match(src, /property string activeWorkspaceName/);
    assert.match(src, /_wsName:\s*root\.activeWorkspaceName !== ""/s);
    assert.match(bar, /activeWorkspaceName:\s*PanelBus\.sceneByScreen\[bar\.screen\.name\]/);
});

// An item's `visible` reports EFFECTIVE visibility in Qt Quick, so a child of
// a hidden parent reads false whatever its own binding says. The bar gates the
// isle's slot on this component, and gating on `visible` made the two lock
// each other off — the roster never appeared. The gate must read a plain fact
// about the desk, never the rendered state it feeds.
test("the bar gates the isle on a fact, not on the roster's rendered visibility", () => {
    assert.match(src, /readonly property bool shouldShow/);
    assert.match(src, /visible:\s*root\.shouldShow/);
    assert.match(bar, /active:\s*roster\.shouldShow/);
    assert.doesNotMatch(bar, /active:\s*roster\.visible/);
});

test("focuses a selected member", () => {
    assert.match(src, /DofusWindows\.focus\(/);
});

// The controls are glyphs now (⌖, ▶/■) with the word in the tooltip, so the
// assertions follow the wiring and the tooltip text rather than a visible
// label that no longer exists.
test("exposes recalibrate, learn, and start/stop controls", () => {
    assert.match(src, /DofusSwap\.calibrate\(/);
    assert.match(src, /DofusSwap\.learn\(/);
    assert.match(src, /DofusSwap\.toggle\(/);
    assert.match(src, /Recalibrate turn-popup region/);
    assert.match(src, /"learn"/);
    assert.match(src, /"Start swap detector"|"Stop swap detector"/);
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

// The roster used to be its own Surface while the bar also wrapped the isle in
// one (Bar.qml's `Island`), so the strip drew a frame inside a frame — taller
// than its neighbours and reading as a different widget. It is content now and
// inherits the bar's material like Workspaces and the clock do.
test("is content inside the bar's island, not a second card", () => {
    assert.doesNotMatch(src, /Surface\s*\{/);
    assert.doesNotMatch(src, /elevation:/);
    assert.match(src, /^RowLayout\s*\{/m);
    assert.match(bar, /elevation:\s*"island"/);
});

// The highlight is only as good as the model behind it. Focus must come from
// the compositor's live `activewindowv2` event rather than only from the poll,
// and the resolution must not go back to the highest focusHistoryID — which is
// the LEAST recently focused member, and why the highlight was wrong.
test("applies focus from the live event, resolved by DofusFocus", () => {
    assert.match(windows, /activewindowv2/);
    assert.match(windows, /_updateFocused/);
    assert.match(windows, /DofusFocus\.activeFromHistory/);
    assert.match(windows, /DofusFocus\.focusedAddress/);
    assert.doesNotMatch(windows, /focusHistoryID > recent/);
});

// A 2s poll that learned nothing new must not re-create every Repeater
// delegate: that is what made the strip re-lay-out and drop hover state.
test("publishes the member list only when it actually changed", () => {
    assert.match(windows, /_sameWindows/);
    assert.match(windows, /if \(!root\._sameWindows\(root\.windows, out\)\) root\.windows = out/);
});
