// PaletteLease resolves a mode's `presentation.palette` against the clock
// (LEO-365): a plain id leases every hour, a `{ day, night }` pair leases per
// side. Day is 7 <= hour < 19 — the same split hypr's `,theme.sh` uses.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { isDaytime, leasedPalette } = loadLibrary("services/PaletteLease.js");

test("daytime is 07:00 (inclusive) through 18:59", () => {
    assert.ok(!isDaytime(6));
    assert.ok(isDaytime(7));
    assert.ok(isDaytime(18));
    assert.ok(!isDaytime(19));
});

test("no palette leases nothing", () => {
    assert.equal(leasedPalette(undefined, 12), "");
    assert.equal(leasedPalette(null, 12), "");
    assert.equal(leasedPalette("", 12), "");
});

test("a plain id leases at every hour, day or night", () => {
    assert.equal(leasedPalette("mocha", 12), "mocha");
    assert.equal(leasedPalette("mocha", 2), "mocha");
});

test("a pair leases the day half by day and the night half by night", () => {
    const pair = { day: "latte", night: "mocha" };
    assert.equal(leasedPalette(pair, 7), "latte");
    assert.equal(leasedPalette(pair, 18), "latte");
    assert.equal(leasedPalette(pair, 19), "mocha");
    assert.equal(leasedPalette(pair, 6), "mocha");
});
