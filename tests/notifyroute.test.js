// Notification identity and routing.
//
// The daemon sees every notification on the desk, so a wrong verdict here is
// either an interruption during deep work or a missed critical alert. Both are
// worse than the toast looking slightly wrong.
//
// Identity is the load-bearing half: `app_name` is self-reported free text, so
// a routing table keyed on it cannot be maintained. These tests pin the
// resolution chain that replaces it.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadLibrary } from "./qml.js";

const { source, verdict, route } = loadLibrary("services/NotifyRoute.js");
// `TIER` is named explicitly because the auto-detected export list only finds
// functions, and `TIER` is a table.
const { TIER } = loadLibrary("services/NotifyRoute.js", ["TIER"]);
const { routes } = loadLibrary("services/HyprfocusRead.js");
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const shipped = JSON.parse(
    readFileSync(join(root, "assets/hyprfocus.default.json"), "utf8"),
);

const n = over => ({ appName: "", desktopEntry: "", hints: {}, urgency: "normal", ...over });

test("a desktop entry wins, because the toolkit sets it and the sender cannot pick it freely", () => {
    const r = source(n({ desktopEntry: "org.gnome.Nautilus.desktop", appName: "Files" }));
    assert.equal(r.id, "org.gnome.nautilus");
    assert.equal(r.tier, 1);
    assert.ok(r.trusted);
});

test("the desktop entry is read from hints when not exposed as a property", () => {
    assert.equal(source(n({ hints: { "desktop-entry": "obsidian" } })).id, "obsidian");
});

test("our own hint is next, so a script can identify itself stably", () => {
    // Scripts have no desktop entry. Naming the thing rather than the file
    // means moving the code does not change the routing.
    const r = source(n({ appName: "notify-send", hints: { "x-hyprfocus-source": "linear-sync" } }));
    assert.equal(r.id, "linear-sync");
    assert.equal(r.tier, 2);
    assert.ok(r.trusted);
});

test("the spec's category is next", () => {
    const r = source(n({ appName: "whatever", hints: { category: "email.arrived" } }));
    assert.equal(r.id, "email.arrived");
    assert.equal(r.tier, 3);
});

test("app name is last and is recorded as untrusted", () => {
    const r = source(n({ appName: "Spotify" }));
    assert.equal(r.id, "spotify");
    assert.equal(r.tier, 4);
    assert.equal(r.trusted, false, "the sender chose this string itself");
});

test("a sender identifying itself as nothing still resolves", () => {
    const r = source(n({}));
    assert.equal(r.id, "unknown");
    assert.ok(!r.trusted);
});

test("routes match the source id before anything else", () => {
    const routes = { "linear-sync": "digest", default: "show" };
    const r = route(n({ hints: { "x-hyprfocus-source": "linear-sync" } }), routes);
    assert.equal(r.verdict, "digest");
    assert.equal(r.rule, "linear-sync");
});

test("a category family matches when the exact category does not", () => {
    // `email` catches email.arrived and email.bounced without listing both.
    const r = route(n({ appName: "mail", hints: { category: "email.arrived" } }), { email: "queue" });
    assert.equal(r.verdict, "queue");
    assert.equal(r.rule, "email");
});

test("a category carried on the record routes the same as one in hints", () => {
    // The daemon keeps `category` on the record rather than the sender's whole
    // hint map, so the verdict must read both shapes identically.
    const hinted = route(n({ appName: "some-client", hints: { category: "im.received" } }), { im: "drop" });
    const rec = route({ appName: "some-client", desktopEntry: "", hints: {}, category: "im.received", urgency: "normal" }, { im: "drop" });
    assert.equal(hinted.verdict, "drop");
    assert.equal(rec.verdict, hinted.verdict);
    assert.equal(rec.rule, hinted.rule);
});

test("an exact category beats its family", () => {
    const routes = { email: "drop", "email.arrived": "show" };
    assert.equal(route(n({ appName: "mail", hints: { category: "email.arrived" } }), routes).verdict, "show");
});

test("the mode's default applies to anything unmatched", () => {
    assert.equal(route(n({ appName: "random" }), { default: "drop" }).verdict, "drop");
});

test("showing is the fallback when a mode declares no default", () => {
    // Silence should be chosen, never inherited from an empty table.
    assert.equal(route(n({ appName: "random" }), {}).verdict, "show");
});

test("urgency is never identity", () => {
    // Two notifications differing only in urgency resolve to the same source.
    const a = source(n({ appName: "x", urgency: "critical" }));
    const b = source(n({ appName: "x", urgency: "low" }));
    assert.equal(a.id, b.id);
});

test("a critical notification escalates out of silence", () => {
    // A mode that hides "battery at 2%" is not reducing distraction, it is
    // withholding something needed.
    const r = route(n({ appName: "upower", urgency: "critical" }), { default: "drop" });
    assert.equal(r.verdict, "show");
    assert.ok(r.escalated);
});

test("critical escalation can be turned off deliberately", () => {
    const routes = { default: "drop", "allow-critical-suppression": true };
    const r = route(n({ appName: "upower", urgency: "critical" }), routes);
    assert.equal(r.verdict, "drop");
    assert.ok(!r.escalated);
});

test("a critical notification already routed to show is not marked escalated", () => {
    const r = route(n({ appName: "upower", urgency: "critical" }), { default: "show" });
    assert.equal(r.verdict, "show");
    assert.ok(!r.escalated);
});

test("every routed notification carries what decided it", () => {
    // History is never conditional: a mode that hid something must be able to
    // show you what it hid, and why.
    const r = route(n({ hints: { "x-hyprfocus-source": "linear-sync" } }), { default: "queue" });
    assert.deepEqual(Object.keys(r).sort(), ["escalated", "rule", "source", "tier", "trusted", "verdict"]);
});

test("ids are normalised so case and suffix cannot split one sender in two", () => {
    assert.equal(source(n({ desktopEntry: "Obsidian.desktop" })).id, "obsidian");
    assert.equal(source(n({ appName: "  Spotify  " })).id, "spotify");
});

// The mode acceptance case, against the shipped declaration: gaming drops
// chat, queues the sync's results, and still shows a critical battery
// warning — and every one of them is recorded with the rule that decided it.
const gaming = routes(shipped, "gaming");

test("gaming drops a chat toast", () => {
    // A client without a desktop entry that declares the spec's vocabulary
    // resolves at category tier and matches through the family rule.
    const r = route(n({ appName: "some-client", hints: { category: "im.received" } }), gaming);
    assert.equal(r.verdict, "drop");
    assert.equal(r.rule, "im");
});

test("gaming queues the sync's results, though the mode stops the sync itself", () => {
    const r = route(n({ appName: "notify-send", hints: { "x-hyprfocus-source": "linear-sync" } }), gaming);
    assert.equal(r.verdict, "queue");
    assert.equal(r.rule, "linear-sync");
});

test("gaming drops at its default but a critical still shows", () => {
    const r = route(n({ appName: "upower", urgency: "critical" }), gaming);
    assert.equal(r.verdict, "show");
    assert.ok(r.escalated, "battery at 2% is not distraction");
});

test("gaming drops an app that never states what it is", () => {
    // The untrusted last resort still resolves — and the mode verdict then
    // decides, so the sender is a name in history rather than a mystery.
    const r = route(n({ appName: "Steam" }), gaming);
    assert.equal(r.verdict, "drop");
    assert.equal(r.source, "steam");
    assert.equal(r.tier, TIER.APP_NAME);
    assert.ok(!r.trusted);
});
