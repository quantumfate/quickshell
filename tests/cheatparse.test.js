// The cheatsheet parser.
//
// Both the full overlay and the passive peek render whatever this returns, so a
// parsing change shows up as a cheatsheet that quietly lists the wrong binds —
// the one surface you consult precisely when you do not know what is bound.
//
// The fixture is real `hyprctl binds -j` output, reduced to the fields the
// parser reads. If Hyprland changes that shape, these tests fail instead of the
// panel going blank.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadLibrary } from "./qml.js";

const { combo, categorize, parse, splitColumns, contextTag, matchesContext, breadcrumb } =
    loadLibrary("modules/cheatsheet/CheatParse.js");

const here = dirname(fileURLToPath(import.meta.url));
const fixture = readFileSync(join(here, "fixtures/binds.json"), "utf8");
const ORDER = ["Window", "Workspace", "Menus", "Media", "Utilities", "Dofus", "Shell", "General"];

test("modmask decodes to modifier names", () => {
    assert.equal(combo(0, "A"), "A");
    assert.equal(combo(64, "slash"), "SUPER + slash");
    assert.equal(combo(65, "k"), "SHIFT + SUPER + k");     // 1 | 64
    assert.equal(combo(72, "m"), "ALT + SUPER + m");        // 8 | 64
    assert.equal(combo(4 | 8 | 64, "p"), "CTRL + ALT + SUPER + p");
});

test("an explicit Category: prefix wins over keyword matching", () => {
    // "Window" would also match the keyword bucket; the prefix must take it and
    // strip itself from the label.
    assert.deepEqual(categorize("Scrolling: fit the active column"), {
        cat: "Scrolling",
        label: "fit the active column"
    });
});

test("descriptions bucket by keyword when unprefixed", () => {
    assert.equal(categorize("Volume up").cat, "Media");
    assert.equal(categorize("Close focused window").cat, "Window");
    assert.equal(categorize("Focus workspace 5").cat, "Workspace");
    assert.equal(categorize("Screenshot a selected region").cat, "Utilities");
    assert.equal(categorize("Something entirely unheard of").cat, "General");
});

test("a trailing ellipsis marks a submenu", () => {
    assert.equal(categorize("Applications…").cat, "Menus");
    assert.equal(categorize("Applications...").cat, "Menus");
});

test("the root context excludes binds belonging to a submap", () => {
    const rows = parse(fixture, "", ORDER).flatMap(c => c.rows);
    assert.ok(rows.length > 0, "no root binds parsed from the fixture");

    const inSubmaps = JSON.parse(fixture).filter(b => b.description && b.submap);
    assert.ok(inSubmaps.length > 0, "fixture has no submap binds to exclude");
    for (const bind of inSubmaps) {
        assert.ok(
            !rows.some(r => r.combo === combo(bind.modmask || 0, bind.key) && r.desc.endsWith(bind.description)),
            `submap bind "${bind.description}" leaked into the root context`
        );
    }
});

test("a submap context shows only its own binds", () => {
    const cats = parse(fixture, "project", ORDER);
    const rows = cats.flatMap(c => c.rows);
    assert.ok(rows.length > 0, "the project submap parsed empty");

    const expected = JSON.parse(fixture).filter(b => b.description && b.submap === "project");
    assert.equal(rows.length, expected.length, "row count does not match the fixture");
});

test("undescribed binds never reach the panel", () => {
    const rows = parse(fixture, "", ORDER).flatMap(c => c.rows);
    assert.ok(rows.every(r => r.desc && r.desc.length > 0));
});

test("categories follow the configured order, unlisted ones alphabetically after", () => {
    const names = parse(fixture, "", ORDER).map(c => c.name);
    const known = names.filter(n => ORDER.includes(n));
    const unknown = names.filter(n => !ORDER.includes(n));

    assert.deepEqual(known, [...known].sort((a, b) => ORDER.indexOf(a) - ORDER.indexOf(b)));
    assert.deepEqual(unknown, [...unknown].sort());
    // Every unlisted category sorts after every listed one.
    if (known.length && unknown.length) {
        assert.ok(names.lastIndexOf(known.at(-1)) < names.indexOf(unknown[0]));
    }
});

test("identical binds are shown once", () => {
    const rows = parse(fixture, "", ORDER).flatMap(c => c.rows);
    const keys = rows.map(r => r.combo + "|" + r.desc);
    assert.equal(new Set(keys).size, keys.length, "duplicate rows in the panel");
});

test("malformed input yields no categories rather than throwing", () => {
    assert.deepEqual(parse("not json at all", "", ORDER), []);
    assert.deepEqual(parse("", "", ORDER), []);
});

test("columns are balanced by rendered height, not category count", () => {
    const cats = parse(fixture, "", ORDER);
    const [left, right] = splitColumns(cats);

    assert.equal(left.length + right.length, cats.length, "a category was dropped");

    const height = col => col.reduce((n, c) => n + c.rows.length + 1, 0);
    const tallest = Math.max(...cats.map(c => c.rows.length + 1));
    assert.ok(
        Math.abs(height(left) - height(right)) <= tallest,
        `columns differ by more than the tallest category (${height(left)} vs ${height(right)})`
    );
});

test("splitColumns tolerates an empty list", () => {
    assert.deepEqual(splitColumns([]), [[], []]);
    assert.deepEqual(splitColumns(undefined), [[], []]);
});

test("Dofus-category binds are tagged gaming; group mentions are tagged group", () => {
    assert.equal(contextTag("Dofus", "activate team member 1"), "gaming");
    assert.equal(contextTag("Window", "Close focused window"), null);
    assert.equal(contextTag("Window", "Cycle group tab"), "group");
    assert.equal(contextTag("Window", "Toggle grouped state"), "group");
});

test("matchesContext gates gaming/group tags on the live desk, passes everything else", () => {
    assert.equal(matchesContext("gaming", { gaming: false }), false);
    assert.equal(matchesContext("gaming", { gaming: true }), true);
    assert.equal(matchesContext("group", { grouped: false }), false);
    assert.equal(matchesContext("group", { grouped: true }), true);
    assert.equal(matchesContext(null, {}), true);
});

test("parse hides gaming binds off the gaming workspace, without greying them", () => {
    const off = parse(fixture, "", ORDER, { gaming: false }).flatMap(c => c.rows);
    assert.ok(off.every(r => !r.desc.toLowerCase().includes("team member")));

    const on = parse(fixture, "", ORDER, { gaming: true }).flatMap(c => c.rows);
    assert.ok(on.some(r => r.desc.toLowerCase().includes("team member")));
});

test("parse with no ctx behaves as if nothing is gaming/grouped", () => {
    const noCtx = parse(fixture, "", ORDER).flatMap(c => c.rows);
    const offCtx = parse(fixture, "", ORDER, { gaming: false, grouped: false }).flatMap(c => c.rows);
    assert.deepEqual(noCtx, offCtx);
});

test("breadcrumb renders the four-tuple, dashing out whatever is missing", () => {
    assert.equal(breadcrumb({}), "— › — › — › —");
    assert.equal(
        breadcrumb({ workspace: "gaming", windowClass: "Dofus.x64", grouped: true, layout: "dwindle" }),
        "gaming › Dofus.x64 › grouped › dwindle"
    );
    assert.equal(
        breadcrumb({ workspace: "1", windowClass: "kitty", grouped: false, layout: "scrolling" }),
        "1 › kitty › — › scrolling"
    );
});
