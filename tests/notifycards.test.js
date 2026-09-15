// The routed notification centre's display model (LEO-240).
//
// History is never conditional, so the panel can answer what a mode hid —
// but only if it reads the resolved source, the tier, the verdict and the
// rule that decided, rather than grouping by the app's own claim about
// itself. These tests build the words once, from the record shape history
// keeps.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { sender, tierLine, routeLine, verdict, verdictRole } = loadLibrary("services/NotifyCards.js");

test("the panel names the resolved source, not the app's claim", () => {
    assert.equal(sender({ source: "obsidian", tier: 1, trusted: true }), "obsidian");
});

test("an app-name resolution is named with it, as the untrusted thing it is", () => {
    // The sender claimed the string itself; the card records both the claim
    // and the resolution so the source is visible rather than mysterious.
    assert.equal(
        sender({ source: "spotify", tier: 4, trusted: false, appName: "Spotify" }),
        "spotify (claimed: Spotify)",
    );
});

test("a sender that never claimed anything is still named", () => {
    assert.equal(sender({ source: "unknown", tier: 5, trusted: false }), "unknown (untrusted)");
});

test("tier words read what they resolved from", () => {
    assert.equal(tierLine({ tier: 1 }), "desktop entry");
    assert.equal(tierLine({ tier: 2 }), "hyprfocus source");
    assert.equal(tierLine({ tier: 3 }), "category");
    assert.equal(tierLine({ tier: 4 }), "app name");
    assert.equal(tierLine({}), "unknown");
});

test("a shown notification reads plainly", () => {
    assert.equal(routeLine({}), "shown");
    assert.equal(routeLine({ route: "shown" }), "shown");
});

test("holds name what held them", () => {
    assert.equal(routeLine({ route: "dnd" }), "held by do-not-disturb");
    assert.equal(routeLine({ route: "mood" }), "held by the mode's policy");
});

test("the verdict line names the rule that decided", () => {
    assert.equal(
        routeLine({ route: "mode:queue", rule: "linear-sync" }),
        "queued by rule 'linear-sync'",
    );
    assert.equal(routeLine({ route: "mode:digest", rule: "default" }), "counted only");
    assert.equal(routeLine({ route: "mode:drop", rule: "im" }), "dropped by rule 'im'");
});

test("an escalated critical says so in the verdict line", () => {
    // A mode that hid battery-at-2% would have to escalate; the line says the
    // rule was overridden, not that everything was silence.
    assert.equal(
        routeLine({ route: "mode:drop", rule: "default", escalated: true }),
        "dropped (critical escalated)",
    );
});

test("verdicts badge", () => {
    assert.equal(verdict("shown"), "shown");
    assert.equal(verdict(""), "shown");
    assert.equal(verdict("dnd"), "held");
    assert.equal(verdict("mode:queue"), "queue");
    assert.equal(verdict("mode:drop"), "drop");
    assert.equal(verdict(undefined), "shown", "a legacy entry reads as shown");
});

test("badge colour: the verdict first, the shell level when no verdict decided", () => {
    assert.equal(verdictRole("mode:drop"), "error");
    assert.equal(verdictRole("mode:queue"), "pending");
    assert.equal(verdictRole("mode:digest"), "pending");
    assert.equal(verdict("dnd") && "held", "held");
    assert.equal(verdictRole("shown", "error"), "error");
    assert.equal(verdictRole("shown", "success"), "success");
    assert.equal(verdictRole("shown"), "accent");
    assert.equal(verdictRole(undefined, "error"), "error", "a legacy entry reads by level too");
});
