// mood-policy.json's contract (LEO-236 + LEO-237): the mood-mode policy store.
//
// One definitional store keyed by the six moods, recording what each mood
// allows, changes, or suppresses. Since LEO-237 the store IS the source of
// truth for the shell — Focus.qml's `policyDefaults` literal seeds it, and the
// shipped asset must be that literal's exact serialization. The load-bearing
// invariants, all pinned with no JSON Schema validator in the toolchain (same
// constraint as focus.test.js):
//
//   1. Focus.qml's `policyDefaults` literal and assets/mood-policy.default.json
//      are identical — the shell seeds from one and hypr/scripts read the
//      other; a divergence is a deployment bug. (This replaced the old
//      casing-normalized lockstep the moment Focus stopped owning a separate
//      camelCase table.)
//   2. The mood set matches focus.schema.json's `mode` enum.
//   3. Every mood record is valid against the schema, with sane enumeration
//      values and non-duplicated block lists.
//   4. Launch semantics reproduce Focus.canLaunch exactly: a mood never
//      refuses itself, neutral never blocks, every other mood is firm on the
//      same `blockedKinds` minus itself — gaming excepted, which since this
//      revision lets a media browser through (Zen media while gaming).
//   5. The background defaults change nothing until configured — policy
//      allow, `["*"]`, nothing deferred or prevented.
//   6. Scene reachability is per-mood and minimal: absent is reachable, so
//      only what a mood takes away appears (work/study drop gaming+media).
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

/** Parses Focus.qml's `policyDefaults` literal the way focus.test.js does. */
function loadPolicy() {
    const start = focusSrc.indexOf("readonly property var policyDefaults:");
    if (start === -1) throw new Error("Focus.qml: no `policyDefaults` property found");
    const open = focusSrc.indexOf("({", start);
    let depth = 0, end = -1;
    for (let i = open + 1; i < focusSrc.length; i++) {
        if (focusSrc[i] === "{") depth++;
        else if (focusSrc[i] === "}") { depth--; if (depth === 0) { end = i; break; } }
    }
    if (end === -1) throw new Error("Focus.qml: unterminated `policyDefaults` object");
    return eval("(" + focusSrc.slice(open + 1, end + 1) + ")");
}

const policy = loadPolicy();

test("Focus.qml's policyDefaults is byte-identical to the shipped default asset", () => {
    // The core lockstep since LEO-237: Focus seeds the store from this literal
    // and hypr/scripts read the asset, so both describe one policy. Any edit
    // must land in both places — this test is the tripwire.
    assert.deepEqual(policy, defaults, "Focus.qml's `policyDefaults` differs from assets/mood-policy.default.json");
});

test("the mood set is identical across the schema, the default, and Focus.qml", () => {
    assert.deepEqual(Object.keys(moods).sort(), [...moodEnum].sort(),
        "mood-policy.default.json does not enumerate focus.schema's moods");
    assert.deepEqual(Object.keys(policy.moods).sort(), [...moodEnum].sort(),
        "Focus.qml's policyDefaults does not enumerate focus.schema's moods");
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
        // LEO-252 retired policy/allow: the background section is defer/prevent lists.
        assert.deepEqual(Object.keys(mood.background).sort(), ["defer", "prevent"],
            `mood "${mode}" background "${JSON.stringify(mood.background)}"`);
        for (const [scene, state] of Object.entries(mood.scenes)) {
            assert.ok(["reachable", "blocked", "limited"].includes(state),
                `mood "${mode}" scene "${scene}" has unknown state "${state}"`);
        }
    }
});

test("launch policy reproduces Focus.canLaunch exactly", () => {
    // Focus.canLaunch: a mood never blocks launching into itself; neutral
    // never blocks; every other mood refuses blockedKinds minus itself (soft
    // moods warn and let through — but none of the defaults are soft except
    // neutral, which blocks nothing). Gaming does NOT refuse media: a
    // media browser (Zen) stays launchable while gaming.
    const blockedKinds = ["media", "game"];
    // The launch kind a mood id owns (Focus.qml's kindOwner): the game kind
    // belongs to the gaming mood, however the two vocabularies spell it.
    const kindOwner = { game: "gaming" };
    for (const mode of moodEnum) {
        for (const kind of blockedKinds) {
            const allowed = mode === "neutral" || mode === kind || kindOwner[kind] === mode;
            // A mood never lists a launch Focus would always let it through:
            // blocking your own kind is a lock-out, not a policy.
            if (allowed) {
                assert.ok(!moods[mode].launches.block.includes(kind),
                    `${mode} lists its own launch "${kind}" in launches.block`);
            }
        }
    }
    // And the refusals the defaults intend hold: work and study are firm on
    // both kinds; gaming names nothing, so the media browser stays launchable.
    for (const mode of ["work", "study"]) {
        assert.ok(moods[mode].launches.block.includes("media"), `${mode} refuses media`);
        assert.ok(moods[mode].launches.block.includes("game"), `${mode} refuses game`);
        assert.equal(moods[mode].launches.aggression, "firm", `${mode} refusal is firm`);
        assert.equal(moods[mode].launches.override, true, `${mode} honours an explicit override key`);
    }
    assert.deepEqual(moods.gaming.launches.block, [], "gaming keeps the media browser launchable");
    assert.equal(moods.neutral.launches.aggression, "soft",
        "neutral blocks nothing and has no reason to be strict");
    assert.equal(moods.neutral.launches.override, false,
        "a mood with nothing to refuse has no override");
    for (const mode of ["work", "study", "gaming"]) {
        assert.equal(moods[mode].launches.aggression, "firm",
            `${mode} should stay firm (open decision #3 baseline)`);
        assert.equal(moods[mode].launches.override, true,
            `${mode} firm refusal should honour an explicit override key`);
    }
});

test("background defaults change nothing until configured", () => {
    for (const mode of moodEnum) {
        const bg = moods[mode].background;
        assert.deepEqual(bg.defer, [], `${mode} defers something by default`);
        assert.deepEqual(bg.prevent, [], `${mode} prevents something by default`);
        // Anything not listed runs: the wildcard/policy vocabulary is gone.
        for (const key of ["policy", "allow"]) {
            assert.ok(!(key in bg), `${mode} carries the retired background "${key}" shape`);
        }
    }
});

test("scene reachability is per-mood and only lists what a mood takes away", () => {
    assert.deepEqual(moods.neutral.scenes, {}, "neutral restricts no scenes");
    for (const mode of ["work", "study"]) {
        assert.equal(moods[mode].scenes.gaming, "blocked", `${mode} should block gaming`);
        assert.equal(moods[mode].scenes.media, "blocked", `${mode} should block media`);
    }
    assert.equal(moods.gaming.scenes.gaming, "reachable", "gaming must not lock itself out");
    assert.equal(moods.gaming.scenes.media, undefined, "an unlisted scene stays reachable");
});

// Extracts a named function's body from Focus.qml, stopping at its closing
// brace (a plain `[\s\S]*?\}` non-greedy capture would stop at the first inline
// `{}` object literal, e.g. `const bg = ... || {};`).
function fnBody(name) {
    const m = focusSrc.match(new RegExp("function " + name + "\\([^)]*\\) \\{([\\s\\S]*?)\\n    \\}\\n"));
    return m?.[1] ?? "";
}

test("sceneState resolves absent = reachable and only 'blocked' takes a scene away", () => {
    // The oracle the workspace gates read (`focus scene <name>`). The policy
    // literal is the entire table: every mood x every scene must be a known
    // state, and the active mood never locks its own scene out.
    const fn = fnBody("sceneState");
    assert.match(fn, /!root\.active/, "an inactive mood must leave every scene reachable");
    assert.match(fn, /root\.current\.scenes/, "sceneState must read the active mood's scenes");
    for (const mode of moodEnum) {
        for (const scene of ["gaming", "media"]) {
            const state = moods[mode].scenes[scene] || "reachable";
            assert.ok(["reachable", "blocked"].includes(state),
                `${mode} names unknown scene state "${state}" for "${scene}"`);
        }
    }
});

test("backgroundTaskLevel is one resolver: prevent beats defer, not-listed runs", () => {
    const fn = fnBody("backgroundTaskLevel");
    assert.match(fn, /if \(!root\.active\) return "allow";/, "the resting mood must allow all background work");
    assert.match(fn, /prevent\.indexOf\(task\) >= 0/, "prevent must be checked before defer");
    assert.match(fn, /defer\.indexOf\(task\) >= 0/, "defer must be checked before the unset fallthrough");
    // The default policy gates nothing and restricts nothing per mood.
    for (const mode of moodEnum) {
        assert.deepEqual(moods[mode].background.defer, [], `${mode} defers something by default`);
        assert.deepEqual(moods[mode].background.prevent, [], `${mode} prevents something by default`);
    }
});