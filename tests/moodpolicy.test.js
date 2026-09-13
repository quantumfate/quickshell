// mood-policy.json's contract (LEO-236): the mood-mode policy store.
//
// One definitional store keyed by the six moods, recording what each mood
// allows, changes, or suppresses. The load-bearing invariants, all pinned with
// no JSON Schema validator in the toolchain (same constraint as focus.test.js
// and scenes.test.js):
//
//   1. The store and the runtime agree on which moods exist — mood set must be
//      identical to focus.schema.json's `mode` enum AND to Focus.qml's `moods`
//      table.
//   2. The visual + notification fields are lockstep copies of Focus.qml's
//      table (normalized casing), so the store cannot drift from the shell
//      that still owns them until LEO-237 flips the direction.
//   3. Launch semantics reproduce Focus.canLaunch exactly: a mood never
//      refuses itself, neutral never blocks, every other mood is firm on the
//      same `blockedKinds` minus itself.
//   4. The background defaults change nothing until configured — policy
//      allow, `["*"]`, nothing deferred or prevented. Adopting the store must
//      not alter live behavior.
//   5. Scene reachability is per-mood and minimal: absent is reachable, so
//      only what a mood takes away appears (deep/reflect drop gaming+media).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = p => JSON.parse(readFileSync(join(root, p), "utf8"));

const schema = read("schemas/mood-policy.schema.json");
const defaults = read("assets/mood-policy.default.json");
const focusSchema = read("schemas/focus.schema.json");
const focusSrc = readFileSync(join(root, "services/Focus.qml"), "utf8");
const moods = defaults.moods;

const moodProps = Object.keys(schema.definitions.mood.properties);
const moodEnum = focusSchema.properties.mode.enum;

/** Parses Focus.qml's `moods` object the same way focus.test.js does. */
function loadMoods() {
    const start = focusSrc.indexOf("readonly property var moods:");
    if (start === -1) throw new Error("Focus.qml: no `moods` property found");
    const open = focusSrc.indexOf("({", start);
    let depth = 0, end = -1;
    for (let i = open + 1; i < focusSrc.length; i++) {
        if (focusSrc[i] === "{") depth++;
        else if (focusSrc[i] === "}") { depth--; if (depth === 0) { end = i; break; } }
    }
    if (end === -1) throw new Error("Focus.qml: unterminated `moods` object");
    return eval("(" + focusSrc.slice(open + 1, end + 1) + ")");
}

// Normalize Focus.qml's camelCase field names to the store's snake_case.
const SNAKE = {
    accentRole: "accent_role",
    surfaceAlpha: "surface_alpha",
    motionEnergy: "motion_energy",
    barAutohide: "bar_autohide",
    digestOnExit: "digest_on_exit",
};

test("the mood set is identical across the schema, the default, and Focus.qml", () => {
    const qml = loadMoods();
    assert.deepEqual(Object.keys(moods).sort(), [...moodEnum].sort(),
        "mood-policy.default.json does not enumerate focus.schema's moods");
    assert.deepEqual(Object.keys(qml).sort(), [...moodEnum].sort(),
        "Focus.qml's moods table does not enumerate focus.schema's moods");
});

test("every mood record is a valid record against the schema", () => {
    for (const [mode, mood] of Object.entries(moods)) {
        const unknown = Object.keys(mood).filter(k => !moodProps.includes(k));
        assert.deepEqual(unknown, [], `mood "${mode}" carries fields the policy does not define`);
        for (const required of ["name", "notifications", "launches", "background", "scenes"]) {
            assert.ok(required in mood, `mood "${mode}" is missing "${required}"`);
        }
        assert.ok(["soft", "firm", "hard"].includes(mood.launches.aggression),
            `mood "${mode}" aggression "${mood.launches.aggression}"`);
        assert.equal(new Set(mood.launches.block).size, mood.launches.block.length,
            `mood "${mode}" lists a launch category twice`);
        assert.ok(["all", "critical-only", "none"].includes(mood.notifications.policy),
            `mood "${mode}" notification policy "${mood.notifications.policy}"`);
        assert.ok(["allow", "deny"].includes(mood.background.policy),
            `mood "${mode}" background policy "${mood.background.policy}"`);
        for (const [scene, state] of Object.entries(mood.scenes)) {
            assert.ok(["reachable", "blocked", "limited"].includes(state),
                `mood "${mode}" scene "${scene}" has unknown state "${state}"`);
        }
    }
});

test("visual and notification fields are lockstep copies of Focus.qml", () => {
    const qml = loadMoods();
    for (const mode of moodEnum) {
        const src = qml[mode];
        const stored = moods[mode];
        assert.equal(stored.name, src.name, `${mode} name differs`);
        assert.equal(stored.accent_role, src.accentRole, `${mode} accent_role differs`);
        assert.equal(stored.surface_alpha, src.surfaceAlpha, `${mode} surface_alpha differs`);
        assert.equal(stored.density, src.density, `${mode} density differs`);
        assert.equal(stored.motion_energy, src.motionEnergy, `${mode} motion_energy differs`);
        assert.equal(stored.bar_autohide, src.barAutohide, `${mode} bar_autohide differs`);
        const qmlNotification = { digest_on_exit: "digestOnExit" };
        for (const field of ["policy", "position", "timeout", "queue", "digest_on_exit"]) {
            assert.deepEqual(stored.notifications[field],
                src.notifications[qmlNotification[field] || field],
                `${mode} notifications.${field} differs`);
        }
    }
});

test("launch policy reproduces Focus.canLaunch exactly", () => {
    // Focus.qml: a mood never blocks launching into itself; neutral never
    // blocks; every non-neutral mood blocks blockedKinds minus itself. The
    // store must be able to express that for each mood.
    const blockedKinds = ["media", "game"];
    for (const mode of moodEnum) {
        for (const kind of blockedKinds) {
            const blocksKind = moods[mode].launches.block.includes(kind);
            const focusAllows = mode === "neutral" || mode === kind;
            assert.equal(blocksKind, !focusAllows,
                `${mode} ${blocksKind ? "blocks" : "allows"} "${kind}", Focus.allows=${focusAllows}`);
        }
    }
    assert.equal(moods.neutral.launches.aggression, "soft",
        "neutral blocks nothing and has no reason to be strict");
    assert.equal(moods.neutral.launches.override, false,
        "a mood with nothing to refuse has no override");
    for (const mode of ["deep", "chores", "reflect", "game", "media"]) {
        assert.equal(moods[mode].launches.aggression, "firm",
            `${mode} should stay firm (open decision #3 baseline)`);
        assert.equal(moods[mode].launches.override, true,
            `${mode} firm refusal should honour an explicit override key`);
    }
});

test("background defaults change nothing until configured", () => {
    for (const mode of moodEnum) {
        const bg = moods[mode].background;
        assert.equal(bg.policy, "allow", `${mode} restricts background work by default`);
        assert.ok(bg.allow.includes("*"), `${mode} does not allow everything`);
        assert.deepEqual(bg.defer, [], `${mode} defers something by default`);
        assert.deepEqual(bg.prevent, [], `${mode} prevents something by default`);
    }
});

test("scene reachability is per-mood and only lists what a mood takes away", () => {
    assert.deepEqual(moods.neutral.scenes, {}, "neutral restricts no scenes");
    assert.deepEqual(moods.chores.scenes, {}, "chores restricts no scenes");
    for (const mode of ["deep", "reflect"]) {
        assert.equal(moods[mode].scenes.gaming, "blocked", `${mode} should block gaming`);
        assert.equal(moods[mode].scenes.media, "blocked", `${mode} should block media`);
    }
    assert.equal(moods.game.scenes.gaming, "reachable", "gaming must not lock itself out");
    assert.equal(moods.media.scenes.media, "reachable", "media must not lock itself out");
});