// sound.json's contract, plus the invariant Sound.qml leans on: mpv can die
// (crash, OOM, a stray pkill) between commands, so every entry point must
// route through _ensureAlive() rather than trust a cached "it's running" flag.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = p => JSON.parse(readFileSync(join(root, p), "utf8"));
const src = readFileSync(join(root, "services/Sound.qml"), "utf8");

const schema = read("schemas/sound.schema.json");
const defaults = read("assets/sound.default.json");

function validate(doc) {
    const errors = [];
    for (const key of schema.required) if (!(key in doc)) errors.push(`${key} missing`);
    if (!schema.properties.mode.enum.includes(doc.mode)) errors.push(`mode "${doc.mode}" not allowed`);
    if (doc.track !== null && typeof doc.track !== "string") errors.push("track is neither string nor null");
    if (typeof doc.volume !== "number" || doc.volume < 0 || doc.volume > 1) errors.push("volume out of range");
    if (doc.pools === undefined) errors.push("pools missing");
    else for (const kind of Object.keys(doc.pools ?? {}))
        if (!schema.properties.pools.additionalProperties.pattern.startsWith("^\\$HOME/") || !doc.pools[kind].startsWith("$HOME/"))
            errors.push(`pool "${kind}" is not a resolved-by-Sound "$HOME/..." path`);
    return errors;
}

test("the shipped defaults satisfy the schema", () => {
    assert.deepEqual(validate(defaults), []);
});

test("defaults start stopped", () => {
    assert.equal(defaults.mode, "off");
    assert.equal(defaults.track, null);
});

test("the schema rejects an unknown mode", () => {
    assert.ok(validate({ mode: "storm", track: null, volume: 0.5 }).length);
});

test("the schema rejects an out-of-range volume", () => {
    assert.ok(validate({ ...defaults, volume: 1.5 }).length);
});

test("every mode the schema allows has a declared pool, and nothing else does", () => {
    // The pool keys are declared data (asset + QML store default, in
    // lockstep); Sound.qml resolves "$HOME/..." at runtime, so the shipped
    // asset is what names the directories.
    const pools = defaults.pools ?? {};
    const kinds = schema.properties.mode.enum.filter(m => m !== "off");
    assert.deepEqual(Object.keys(pools).sort(), [...kinds].sort());
    const literal = src.match(/pools:\s*\{([\s\S]*?)\}/)?.[1] ?? "";
    for (const kind of kinds) {
        assert.ok(literal.includes(`${kind}: "${"$"}HOME`), `Sound.qml's defaults literal has no pool for ${kind}`);
        assert.ok(pools[kind].startsWith("$HOME"), `pool ${kind} must be a "$HOME/..." path`);
    }
});

test("mpv loops the loaded file — a track ending into idle is a broken player, not ambience", () => {
    const spawnCmd = src.match(/spawner\.command = \[[\s\S]*?\];/)?.[0] ?? "";
    assert.ok(spawnCmd.includes("--loop-file=inf"), "the player loop is not declared at spawn");
});

test("each pool directory has a runtime check path", () => {
    // _browse resolves dirs[kind]; a kind the schema allows but no pool
    // names would silently send mpv nothing.
    const browse = src.match(/function _browse\(kind, wantedTrack\) \{([\s\S]*?)\n    \}/)?.[1] ?? "";
    assert.ok(browse.includes("if (!dir) return"), "_browse does not guard against a missing pool");
});

test("every public transport function goes through _ensureAlive before touching mpv", () => {
    // play/pickTrack/next funnel through _browse -> _loadFile -> _send, and
    // stop/setVolume call _send directly; _send is the one place _ensureAlive
    // is called, so mpv dying never has to be handled at each call site.
    const sendBody = src.match(/function _send\(obj\) \{([\s\S]*?)\n    \}/)?.[1] ?? "";
    assert.ok(sendBody.includes("_ensureAlive()"), "_send() does not call _ensureAlive()");
});

test("the mpv probe pattern matches the socket the spawner actually opens", () => {
    const spawnCmd = src.match(/spawner\.command = \[[\s\S]*?\];/)?.[0] ?? "";
    const probeCmd = src.match(/probe\s*\n\s*command: \[[\s\S]*?\]/)?.[0] ?? "";
    assert.ok(spawnCmd.includes("input-ipc-server="), "spawner does not set input-ipc-server");
    assert.ok(probeCmd.includes("input-ipc-server="), "probe does not look for input-ipc-server");
});
