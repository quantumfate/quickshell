// ProjectWindows.js — one entry per open project, from a `hyprctl clients -j`
// snapshot. These are real client shapes, so a regression in the grouping is
// caught without a running shell or compositor.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { normalize, projectName, slotRole, group, forScene } = loadLibrary("services/ProjectWindows.js");

// Two projects, four tabs each, as the compositor reports them mid-session:
// the tags carry Hyprland's own trailing `*`.
const clients = [
    { class: "Proj-hypr", address: "0x1", tags: ["block:code/1*", "scene:code*", "slot:nvim"] },
    { class: "Proj-hypr", address: "0x2", tags: ["slot:yazi"] },
    { class: "Proj-nvim", address: "0x3", tags: ["slot:nvim"] },
    { class: "Kitty-Main", address: "0x4", tags: [] },
    { class: "zen-twilight", address: "0x5" },
];

test("normalize() puts back the 0x an event payload leaves off", () => {
    assert.equal(normalize("55a918"), "0x55a918");
    assert.equal(normalize("0x55a918"), "0x55a918");
    assert.equal(normalize(""), "");
    assert.equal(normalize(null), "");
});

test("projectName() reads the project out of its class", () => {
    assert.equal(projectName("Proj-hypr"), "hypr");
    assert.equal(projectName("Proj-security-and-privacy"), "security-and-privacy");
    assert.equal(projectName("Kitty-Main"), "");
    assert.equal(projectName(""), "");
});

test("projectName() refuses the picker and the confirm prompt", () => {
    // Both wear the project prefix so the scene floats them as strays; neither
    // is a project, and showing either on the bar would be a prompt pretending
    // to be somewhere you can go.
    assert.equal(projectName("Proj-picker"), "");
    assert.equal(projectName("Proj-confirm"), "");
});

test("slotRole() reads a role through Hyprland's trailing star", () => {
    assert.equal(slotRole("slot:nvim"), "nvim");
    assert.equal(slotRole("slot:yazi*"), "yazi");
    assert.equal(slotRole("scene:code*"), "");
    assert.equal(slotRole(""), "");
});

test("group() returns one entry per project, sorted, ignoring everything else", () => {
    const projects = group(clients, "0x1");
    assert.deepEqual(projects.map(p => p.name), ["hypr", "nvim"]);
    assert.deepEqual(projects[0].addresses, ["0x1", "0x2"]);
    assert.deepEqual(projects[0].slots, ["nvim", "yazi"]);
});

test("group() marks exactly the project holding focus", () => {
    const projects = group(clients, "0x3");
    assert.equal(projects.find(p => p.name === "hypr").focused, false);
    assert.equal(projects.find(p => p.name === "nvim").focused, true);
});

test("group() marks a project focused through any of its windows, not just the first", () => {
    const projects = group(clients, "0x2");
    assert.equal(projects.find(p => p.name === "hypr").focused, true);
});

test("clicking a focused project returns to the window you left, not its first", () => {
    const projects = group(clients, "0x2");
    assert.equal(projects.find(p => p.name === "hypr").selector, "address:0x2");
});

test("clicking an unfocused project lands on its first window", () => {
    const projects = group(clients, "0x3");
    assert.equal(projects.find(p => p.name === "hypr").selector, "address:0x1");
});

test("group() is empty when nothing project-classed is open", () => {
    assert.deepEqual(group([{ class: "Kitty-Main", address: "0x4" }], "0x4"), []);
    assert.deepEqual(group([], ""), []);
});

test("group() survives a snapshot with no tags and no focus", () => {
    const projects = group([{ class: "Proj-hypr", address: "0x1" }], "");
    assert.deepEqual(projects[0].slots, []);
    assert.equal(projects[0].focused, false);
    assert.equal(projects[0].selector, "address:0x1");
});

// --- tabs: the strip that replaced the compositor's groupbar ---------------

test("tabs carry one entry per window, in the template's order", () => {
    const projects = group([
        { class: "Proj-hypr", address: "0x3", tags: ["slot:zsh"] },
        { class: "Proj-hypr", address: "0x1", tags: ["slot:nvim"] },
        { class: "Proj-hypr", address: "0x2", tags: ["slot:yazi"] },
    ], "0x2");
    const tabs = projects.find(p => p.name === "hypr").tabs;
    assert.deepEqual(tabs.map(t => t.slot), ["nvim", "yazi", "zsh"]);
});

test("exactly the focused window's tab is marked", () => {
    const projects = group([
        { class: "Proj-hypr", address: "0x1", tags: ["slot:nvim"] },
        { class: "Proj-hypr", address: "0x2", tags: ["slot:yazi"] },
    ], "0x2");
    const tabs = projects.find(p => p.name === "hypr").tabs;
    assert.deepEqual(tabs.map(t => t.focused), [false, true]);
});

test("a window whose slot tag has not landed yet is still a tab, and sorts last", () => {
    const projects = group([
        { class: "Proj-hypr", address: "0x2" },
        { class: "Proj-hypr", address: "0x1", tags: ["slot:nvim"] },
    ], "");
    const tabs = projects.find(p => p.name === "hypr").tabs;
    assert.deepEqual(tabs.map(t => t.slot), ["nvim", ""]);
    assert.deepEqual(tabs.map(t => t.address), ["0x1", "0x2"]);
});

test("clin sorts where the vault declares it, before yazi", () => {
    const projects = group([
        { class: "Proj-test-vault", address: "0x2", tags: ["slot:yazi"] },
        { class: "Proj-test-vault", address: "0x1", tags: ["slot:clin"] },
    ], "");
    assert.deepEqual(projects[0].tabs.map(t => t.slot), ["clin", "yazi"]);
});

// --- scene scoping: a bar describes its own screen's workspace -------------

const twoScenes = [
    { class: "Proj-hypr", address: "0x1", tags: ["slot:nvim", "scene:code*"],
      workspace: { name: "code" } },
    { class: "Proj-dotfiles", address: "0x2", tags: ["slot:nvim", "scene:knowledge*"],
      workspace: { name: "knowledge" } },
];

test("forScene() keeps only the projects standing on that scene", () => {
    const projects = group(twoScenes, "0x2");
    assert.deepEqual(forScene(projects, "code").map(p => p.name), ["hypr"]);
    assert.deepEqual(forScene(projects, "knowledge").map(p => p.name), ["dotfiles"]);
});

test("forScene() ignores which project holds the keyboard", () => {
    // Focus is on the knowledge project; the code screen still describes code.
    const projects = group(twoScenes, "0x2");
    const onCode = forScene(projects, "code");
    assert.equal(onCode.length, 1);
    assert.equal(onCode[0].focused, false);
});

test("forScene() counts a project the deck has parked as still on its scene", () => {
    const parked = group([
        { class: "Proj-hypr", address: "0x1", tags: ["slot:nvim", "scene:code*"],
          workspace: { name: "special:deck-hold" } },
    ], "");
    assert.deepEqual(forScene(parked, "code").map(p => p.name), ["hypr"]);
    assert.deepEqual(forScene(parked, "knowledge"), []);
});

test("forScene() with no scene shows nothing rather than everything", () => {
    assert.deepEqual(forScene(group(twoScenes, ""), ""), []);
});
