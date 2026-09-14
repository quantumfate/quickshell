// focus.json's contract, plus the firm-semantics invariants Focus.qml leans
// on: enforcement reads `mode`/`until` at dispatch time, so a bad shape here
// is a launcher that silently never blocks (or never unblocks). Also covers
// the mood table itself (LEO-227), which since LEO-237 lives in Focus.qml's
// `policyDefaults` literal in the store's snake_case shape: every mood needs an
// accent role that resolves against every palette, since a literal colour here
// would be the one the `tokens` gate exists to catch.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadTheme } from "./qml.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = p => JSON.parse(readFileSync(join(root, p), "utf8"));

const schema = read("schemas/focus.schema.json");
const defaults = read("assets/focus.default.json");
const focusSrc = readFileSync(join(root, "services/Focus.qml"), "utf8");
const { palettes } = loadTheme();

/** Parses Focus.qml's `policyDefaults` literal the same way qml.js parses `palettes`. */
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

const moods = loadPolicy().moods;
const moodEnum = schema.properties.mode.enum;

function validate(doc) {
    const errors = [];
    for (const key of schema.required) if (!(key in doc)) errors.push(`${key} missing`);
    if (schema.properties.mode.enum && !schema.properties.mode.enum.includes(doc.mode)) {
        errors.push(`mode "${doc.mode}" not allowed`);
    }
    if (doc.until !== null && typeof doc.until !== "string") errors.push("until is neither string nor null");
    return errors;
}

test("the shipped defaults satisfy the schema", () => {
    assert.deepEqual(validate(defaults), []);
});

test("defaults start in the neutral state", () => {
    assert.equal(defaults.mode, "neutral");
    assert.equal(defaults.until, null);
});

test("the schema rejects an unknown mode", () => {
    assert.ok(validate({ mode: "paused", until: null }).length);
});

test("the schema's mode enum names exactly the declared moods", () => {
    assert.deepEqual(
        [...moodEnum].sort(),
        ["gaming", "neutral", "study", "work"]
    );
});

test("the kinds any mood refuses are exactly media and game", () => {
    // The union of every mood's launches.block. Focus's derived `blockedKinds`
    // property reads the same table the launchers read, so this is the whole
    // desking surface Focus can ever refuse.
    const kinds = Object.keys(moods)
        .reduce((acc, id) => acc.concat(moods[id].launches.block), [])
        .filter((v, i, a) => a.indexOf(v) === i)
        .sort();
    assert.deepEqual(kinds, ["game", "media"]);
});

test("every mood the schema allows has an entry in Focus.qml's table, and vice versa", () => {
    assert.deepEqual(Object.keys(moods).sort(), [...moodEnum].sort());
});

test("every mood's accent_role resolves against every palette", () => {
    for (const [id, mood] of Object.entries(moods)) {
        for (const palette of Object.keys(palettes)) {
            assert.ok(
                mood.accent_role in palettes[palette],
                `mood "${id}" names accent role "${mood.accent_role}", missing from palette "${palette}"`
            );
        }
    }
});

test("every mood's surface_alpha is a fraction, not a literal colour or a size", () => {
    for (const [id, mood] of Object.entries(moods)) {
        assert.equal(typeof mood.surface_alpha, "number");
        assert.ok(mood.surface_alpha > 0 && mood.surface_alpha <= 1, `mood "${id}" surface_alpha out of range`);
    }
});

test("neutral is defined and is the only resting mood", () => {
    assert.ok(moods.neutral !== undefined, "neutral missing from the policy table");
});

test("a mood never blocks launching into itself", () => {
    // canLaunch(mode) === true whenever mode === kind, for every kind Focus
    // ever blocks — `game` must not refuse a game launch, `media` must not
    // refuse a media launch.
    const fn = focusSrc.match(/function canLaunch\(kind\) \{([\s\S]*?)\}/)?.[1] ?? "";
    assert.match(fn, /root\.mode === kind/, "canLaunch has no self-exemption for the active mood");
});

test("work and study queue notifications and deliver a digest on exit", () => {
    for (const id of ["work", "study"]) {
        assert.equal(moods[id].notifications.queue, true, `${id} should queue notifications`);
        assert.equal(moods[id].notifications.digest_on_exit, true, `${id} should digest on exit`);
    }
});

test("work and study are distinct entries, not aliases of one object", () => {
    // Sanity check that a copy did not fold two moods into a shared reference,
    // which would make "unaffected by every mood except one" impossible to
    // guarantee.
    assert.notEqual(moods.work, moods.study);
    assert.notEqual(moods.work.accent_role, moods.study.accent_role);
    assert.notEqual(moods.gaming, moods.work);
    assert.notEqual(moods.gaming.accent_role, moods.work.accent_role);
});

test("the focus IPC exposes scene reachability and background verdicts for dispatchers", () => {
    // The gates (workspace binds, ,scene-apply.sh, ,mood-bg.sh) read the SAME
    // oracles the UI reads — no second interpretation of the policy.
    assert.match(focusSrc, /function scene\(name: string\): string \{ return root\.sceneState\(name\); \}/,
        "IpcHandler lacks the `scene` verdict");
    assert.match(focusSrc, /function bg\(task: string\): string \{ return root\.backgroundTaskLevel\(task\); \}/,
        "IpcHandler lacks the `bg` verdict");
});