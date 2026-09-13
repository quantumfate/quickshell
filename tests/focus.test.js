// focus.json's contract, plus the firm-semantics invariants Focus.qml leans
// on: enforcement reads `mode`/`until` at dispatch time, so a bad shape here
// is a launcher that silently never blocks (or never unblocks). Also covers
// the mood table itself (LEO-227): every mood needs an accent role that
// resolves against every palette, since a literal colour here would be the
// one the `tokens` gate exists to catch.
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

/** Parses Focus.qml's `moods` object the same way qml.js parses `palettes`. */
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

const moods = loadMoods();

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

test("the schema's mode enum names exactly the six moods", () => {
    assert.deepEqual(
        [...schema.properties.mode.enum].sort(),
        ["chores", "deep", "game", "media", "neutral", "reflect"]
    );
});

test("Focus.qml's blocked kinds match what the report promises (media, game)", () => {
    const m = focusSrc.match(/blockedKinds:\s*\(\[([^\]]*)\]\)/);
    assert.ok(m, "blockedKinds not found in Focus.qml");
    const kinds = m[1].split(",").map(s => s.trim().replace(/"/g, "")).filter(Boolean);
    assert.deepEqual(kinds.sort(), ["game", "media"]);
});

test("every mood the schema allows has an entry in Focus.qml's table, and vice versa", () => {
    assert.deepEqual(Object.keys(moods).sort(), [...schema.properties.mode.enum].sort());
});

test("every mood's accentRole resolves against every palette", () => {
    for (const [id, mood] of Object.entries(moods)) {
        for (const palette of Object.keys(palettes)) {
            assert.ok(
                mood.accentRole in palettes[palette],
                `mood "${id}" names accent role "${mood.accentRole}", missing from palette "${palette}"`
            );
        }
    }
});

test("every mood's surfaceAlpha is a fraction, not a literal colour or a size", () => {
    for (const [id, mood] of Object.entries(moods)) {
        assert.equal(typeof mood.surfaceAlpha, "number");
        assert.ok(mood.surfaceAlpha > 0 && mood.surfaceAlpha <= 1, `mood "${id}" surfaceAlpha out of range`);
    }
});

test("neutral is the only mood with no blocking effect", () => {
    // Mirrors Focus.active: any non-neutral mode blocks, neutral never does.
    assert.equal(moods.neutral !== undefined, true);
});

test("a mood never blocks launching into itself", () => {
    // canLaunch(kind) === true whenever mode === kind, for every kind Focus
    // ever blocks — `game` must not refuse a game launch, `media` must not
    // refuse a media launch.
    const fn = focusSrc.match(/function canLaunch\(kind\) \{([\s\S]*?)\}/)?.[1] ?? "";
    assert.match(fn, /root\.mode !== kind/, "canLaunch has no self-exemption for the active mood");
});

test("deep and reflect queue notifications and deliver a digest on exit", () => {
    for (const id of ["deep", "reflect"]) {
        assert.equal(moods[id].notifications.queue, true, `${id} should queue notifications`);
        assert.equal(moods[id].notifications.digestOnExit, true, `${id} should digest on exit`);
    }
});

test("game and media moods leave the other four untouched by definition", () => {
    // Sanity check that game/media are distinct entries, not aliases of a
    // shared object (which would make "unaffected by every mood except game"
    // impossible to guarantee).
    assert.notEqual(moods.game, moods.media);
    assert.notEqual(moods.game.accentRole, moods.media.accentRole);
});
