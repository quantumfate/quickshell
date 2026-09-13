// scenes.json's contract (LEO-235): the window-scene data model.
//
// Guards three things with no JSON Schema validator in the toolchain (node's
// built-in runner, no deps — same constraint as focus.test.js):
//
//   1. The schema stays honest — every field the model can express is real,
//      and every enum (layout, reevaluate_on, geometry profiles) matches what
//      hypr actually runs (layout_opts.lua namespaces, profile.lua's
//      desk-dual/laptop-solo, the windowrule tag system).
//   2. The seed file is valid against that model and stays *representative*:
//      the scenes it ships (code, gaming, media) are distilled from the live
//      hypr config (hyprland.lua workspace_specs + windowrules.lua), so the
//      contract is grounded in behavior that exists today — not a design for
//      an empty desk.
//   3. The decisions the milestone depends on are pinned, so nothing later
//      silently rebuilds them: scenes are keyed by name, not workspace id;
//      workspace binding is host data; gaming is a scene like any other; the
//      layout can differ per geometry profile (code is dwindle on desk-dual,
//      monocle on laptop-solo).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = p => JSON.parse(readFileSync(join(root, p), "utf8"));

const schema = read("schemas/scenes.schema.json");
const defaults = read("assets/scenes.default.json");
const scenes = defaults.scenes;

const sceneProps = Object.keys(schema.definitions.scene.properties);
const layoutEnum = schema.definitions.layout.enum;
const reevaluateEnum = schema.definitions.reevaluateEvent.enum;
const geometryProfiles = Object.keys(schema.definitions.geometry.properties);

test("the document is exactly { scenes }", () => {
    assert.deepEqual(Object.keys(defaults).sort(), ["scenes"]);
});

test("every scene is a valid record against the schema", () => {
    assert.ok(Object.keys(scenes).length > 0, "the seed file ships no scenes");
    for (const [name, scene] of Object.entries(scenes)) {
        const unknown = Object.keys(scene).filter(k => !sceneProps.includes(k));
        assert.deepEqual(
            unknown, [],
            `scene "${name}" carries fields the model does not define`
        );
        assert.ok("layout" in scene, `scene "${name}" has no base layout`);
        assert.ok(layoutEnum.includes(scene.layout), `scene "${name}" layout "${scene.layout}" is not a running layout`);

        if ("gaps" in scene) {
            assert.deepEqual(Object.keys(scene.gaps).sort(), ["in", "out"], `scene "${name}" gaps`);
        }
        if ("border_size" in scene) {
            assert.equal(typeof scene.border_size, "number", `scene "${name}" border_size`);
        }
        if ("group_default" in scene) {
            assert.ok(["always", "never", "barred"].includes(scene.group_default),
                `scene "${name}" group_default "${scene.group_default}"`);
        }
        if ("reevaluate_on" in scene) {
            for (const ev of scene.reevaluate_on) {
                assert.ok(reevaluateEnum.includes(ev),
                    `scene "${name}" reevaluates on unknown event "${ev}"`);
            }
            assert.equal(new Set(scene.reevaluate_on).size, scene.reevaluate_on.length,
                `scene "${name}" lists a reevaluate_on event twice`);
        }
    }
});

test("member records match the windowrule predicate shape", () => {
    for (const [name, scene] of Object.entries(scenes)) {
        for (const [i, member] of (scene.members || []).entries()) {
            assert.ok(member.match && Object.keys(member.match).length > 0,
                `scene "${name}" member ${i} has an empty match`);
            assert.deepEqual(
                Object.keys(member).filter(k => !["match", "props", "bindings"].includes(k)), [],
                `scene "${name}" member ${i} has unknown keys`
            );
            if ("props" in member) {
                for (const [k, v] of Object.entries(member.props)) {
                    assert.ok(
                        ["string", "boolean", "number"].includes(typeof v) || Array.isArray(v),
                        `scene "${name}" member ${i} prop "${k}" has value ${JSON.stringify(v)}`
                    );
                }
            }
        }
    }
});

test("geometry profiles stay inside the model, with real option keys", () => {
    const desktopKeys = Object.keys(schema.definitions["profile-desktop"].properties);
    const laptopKeys = Object.keys(schema.definitions["profile-laptop"].properties);
    for (const [name, scene] of Object.entries(scenes)) {
        for (const [profile, overrides] of Object.entries(scene.geometry || {})) {
            assert.ok(geometryProfiles.includes(profile),
                `scene "${name}" names unknown geometry profile "${profile}"`);
            const allowed = profile === "laptop-solo" ? laptopKeys : desktopKeys;
            assert.deepEqual(
                Object.keys(overrides).filter(k => !allowed.includes(k)), [],
                `scene "${name}" ${profile} uses a field the profile does not define`
            );
            if ("layout" in overrides) {
                assert.ok(layoutEnum.includes(overrides.layout),
                    `scene "${name}" ${profile} layout "${overrides.layout}" is not a running layout`);
            }
        }
    }
});

test("scenes are keyed by name, not workspace id (host mapping owns ids)", () => {
    for (const [name, scene] of Object.entries(scenes)) {
        assert.ok(!("workspace" in scene),
            `scene "${name}" pins a workspace id — binding is host data in workspace_specs`);
    }
    // The two ids gaming actually needs — name-addressable but id-different per host.
    assert.ok("gaming" in scenes, "the default file must ship the gaming scene");
});

test("gaming is a scene like any other, not a separate configuration path", () => {
    const gaming = scenes.gaming;
    assert.deepEqual(gaming.gaps, { in: 0, out: 0 }, "gaming is borderless on both hosts");
    assert.equal(gaming.border_size, 0);
    assert.equal(gaming.decorate, false);
    assert.equal(gaming.group_default, "always", "the Dofus groupbar is the taskbar");
    assert.equal(gaming.layout, "dwindle");
    assert.ok(gaming.bindings.includes("gaming"), "the which-key context tag is gaming");

    const dofus = gaming.members.find(m => m.match.initial_class === "Dofus.x64");
    assert.ok(dofus, "the Dofus match is part of the gaming scene");
    assert.deepEqual(dofus.props, {
        workspace: "name:gaming",
        group: "set always",
        center: true,
        content: "game",
        opacity: "1.0 override",
        no_anim: true,
        suppress_event: "fullscreen",
    }, "Dofus props are the windowrules.lua group rule, expressed as scene data");
});

test("the profile boundary can swap layouts (the code scene does today)", () => {
    // hyprland.lua: desk-dual runs workspace 1 as dwindle; laptop-solo as monocle.
    // A scene is one name for both, so the divergence must live in geometry.
    const code = scenes.code;
    assert.equal(code.layout, "dwindle");
    assert.equal(code.geometry["laptop-solo"].layout, "monocle");
    assert.equal(code.geometry["desk-dual"], undefined, "desk-dual inherits the base layout");
});