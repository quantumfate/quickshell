// Monitor-routing contract (LEO-328).
//
// Every top-level panel must bind its `screen` to the shared router so bar
// interactions and IPC/keybind interactions land on the right monitor. This is
// a source-level lint: it checks PanelBus exposes the required helpers and that
// each listed panel consumes them.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => readFileSync(join(root, p), "utf8");

const panelBus = read("services/PanelBus.qml");

const PANELS = [
    "modules/bar/NotificationCenter.qml",
    "modules/bar/ProjectsDashboard.qml",
    "modules/bar/CalendarPanel.qml",
    "modules/bar/MoodPanel.qml",
    "modules/bar/SysPanel.qml",
    "modules/bar/Toasts.qml",
    "modules/control/SystemCenter.qml",
    "modules/control/ControlPanel.qml",
    "modules/dofus/TeamSelector.qml",
    "modules/dofus/ClassAssigner.qml",
    "modules/obsidian/ObsidianCreate.qml",
    "modules/cheatsheet/CheatSheet.qml",
    "modules/whichkey/WhichKey.qml",
    "modules/bar/WorkspaceSwitcher.qml",
    "modules/common/WindowRename.qml",
];

test("PanelBus resolves the active monitor from Hyprland's own state", () => {
    assert.match(panelBus, /activeScreen/);
    // LEO-424: event-driven, not a per-second `hyprctl` fork.
    assert.match(panelBus, /Hyprland\.focusedMonitor/);
    assert.doesNotMatch(panelBus, /hyprctl monitors -j/);
});

test("PanelBus exposes a screen object helper with active fallback", () => {
    assert.match(panelBus, /function screenObject\(/);
    assert.match(panelBus, /activeScreen/);
});

test("PanelBus exposes an IPC opener", () => {
    assert.match(panelBus, /function openFromIpc\(/);
});

test("PanelBus carries the isle id for dock-aware panel anchoring", () => {
    assert.match(panelBus, /property string anchorIsleId/);
    assert.match(panelBus, /function toggle\([^)]*isleId/);
});

test("PanelBus shares the per-screen active scene map", () => {
    assert.match(panelBus, /property var sceneByScreen/);
    assert.match(panelBus, /onRawEvent\(/);
});

test("every listed panel binds its screen through PanelBus", () => {
    for (const path of PANELS) {
        const src = read(path);
        assert.match(
            src,
            /screen:\s*PanelBus\.screenObject\(/,
            `${path} does not use PanelBus.screenObject for routing`,
        );
    }
});

test("no panel falls back to an arbitrary Quickshell.screens.find inline", () => {
    for (const path of PANELS) {
        const src = read(path);
        assert.doesNotMatch(
            src,
            /screen:\s*Quickshell\.screens\.find\(/,
            `${path} still uses inline screen resolution`,
        );
    }
});

test("SysMon IPC routes to the active monitor", () => {
    const src = read("services/SysMon.qml");
    assert.match(src, /PanelBus\.activeScreen/);
});

test("Toasts frames itself with the bar's own resting gap resolution", () => {
    const src = read("modules/bar/Toasts.qml");
    assert.match(src, /Store\s*\{\s*id:\s*geometryStore;\s*name:\s*"geometry"/s);
    // Resting inset only (LEO cross-repo "bars never dance"): the monitor's
    // published base gap, same call the bar itself makes. The scene-gap
    // opt-in this used to also ride (BarGaps.sceneGapsFor) is retired.
    assert.match(src, /BarGaps\.insetFor\(/);
    assert.doesNotMatch(src, /BarGaps\.sceneGapsFor\(/);
    assert.match(src, /margins\s*\{[^}]*_topMargin/s);
    assert.match(src, /_leftMargin/);
    assert.match(src, /_rightMargin/);
});

test("Toasts stays below the transition veil and the detail panels", () => {
    const src = read("modules/bar/Toasts.qml");
    // Overlay is the veil's and the panels' layer; a transient card ranks
    // with the bar, so it must never float above them.
    assert.match(src, /WlrLayershell\.layer:\s*WlrLayer\.Top/);
    assert.doesNotMatch(src, /WlrLayershell\.layer:\s*WlrLayer\.Overlay/);
});
