// DofusFocus.js — which member of the Dofus group the roster marks as the
// active tab (services/DofusWindows.qml's `focused`).
//
// This is where the highlight was wrong. `focusHistoryID` 0 is the MOST
// recently focused window and higher is older; the service took the HIGHEST id
// among the group, which is the LEAST recently focused member. These cases are
// real `hyprctl clients -j` shapes, so a regression is caught without a running
// shell.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { normalize, activeFromHistory, focusedAddress } = loadLibrary("services/DofusFocus.js");

// Eight grouped clients as the compositor reports them, with the focus history
// a real switch leaves behind: 0 is the window you just focused.
const clients = [
    { address: "0x55a9185058f0", focusHistoryID: 0 },   // Memoryfracture, active
    { address: "0x55a9184c9cb0", focusHistoryID: 1 },   // Reminiscer
    { address: "0x55a9172dde10", focusHistoryID: 5 },   // Trumafactory
    { address: "0x55a9184a5a70", focusHistoryID: 9 },   // Dissipate
    { address: "0x55a9183bff80", focusHistoryID: 10 },  // Draintouch
    { address: "0x55a917471f10", focusHistoryID: 11 },  // Miserymaker
    { address: "0x55a918605c40", focusHistoryID: 12 },  // Rejecter
    { address: "0x55a9185202b0", focusHistoryID: 13 },  // Sayer
];

const members = clients.map(c => ({ address: c.address }));

test("normalize adds the 0x the raw event omits, and lowercases", () => {
    assert.equal(normalize("55a9185058f0"), "0x55a9185058f0");
    assert.equal(normalize("0x55A9185058F0"), "0x55a9185058f0");
    assert.equal(normalize("0x55a9185058f0"), "0x55a9185058f0");
});

test("normalize reads nothing as nothing", () => {
    assert.equal(normalize(""), "");
    assert.equal(normalize(undefined), "");
    assert.equal(normalize(null), "");
});

// The bug: the active window is the LOWEST id, not the highest. Sayer (13) is
// the least recently focused member and must never be the one picked here.
test("activeFromHistory picks the most recently focused window, not the oldest", () => {
    assert.equal(activeFromHistory(clients), "0x55a9185058f0");
});

test("activeFromHistory ignores windows with no history", () => {
    assert.equal(activeFromHistory([
        { address: "0xaaa", focusHistoryID: -1 },
        { address: "0xbbb", focusHistoryID: 3 },
        { address: "0xccc", focusHistoryID: 7 },
    ]), "0xbbb");
});

test("activeFromHistory tolerates a missing or empty snapshot", () => {
    assert.equal(activeFromHistory([]), "");
    assert.equal(activeFromHistory(undefined), "");
    assert.equal(activeFromHistory([{ address: "0xaaa" }]), "");
});

test("a focused member is the marked tab", () => {
    assert.equal(focusedAddress("0x55a9172dde10", "", members), "0x55a9172dde10");
});

test("the marked tab is matched across the 0x prefix and case", () => {
    assert.equal(focusedAddress("55A9172DDE10", "", members), "0x55a9172dde10");
});

// Another app on the same workspace: the group is unfocused, and the strip
// keeps the member that last held it — what the compositor's groupbar does.
test("focus elsewhere keeps the last member that held it", () => {
    assert.equal(focusedAddress("0x55a9999999", "0x55a9184c9cb0", members), "0x55a9184c9cb0");
});

// Nothing has ever focused a member: the group must still read as one group
// rather than none, so the first member stands in.
test("a group nothing has focused still marks its first member", () => {
    assert.equal(focusedAddress("", "", members), "0x55a9185058f0");
});

test("a last member that is no longer live does not stick", () => {
    assert.equal(focusedAddress("", "0xdeadbeef", members), "0x55a9185058f0");
});

test("no members marks nothing", () => {
    assert.equal(focusedAddress("0x55a9185058f0", "0x55a9184c9cb0", []), "");
});
