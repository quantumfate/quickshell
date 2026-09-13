// The Control Centre's pure logic: wallpaper listing off `ls`, and the
// scale/transparency slider <-> dial-value mapping.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { parseWallpaperList, clamp, scaleFromFraction, fractionFromScale, transparencyFromFraction, moveGridIndex } =
    loadLibrary("modules/control/ControlLogic.js");

test("parseWallpaperList keeps only image files, basenamed and sorted", () => {
    const text = "/home/q/wallpapers/b.png\n/home/q/wallpapers/a.jpg\n/home/q/wallpapers/notes.txt\n\n";
    assert.deepEqual(parseWallpaperList(text), ["a.jpg", "b.png"]);
});

test("parseWallpaperList drops an `ls: cannot access` error line", () => {
    const text = "ls: cannot access '/missing': No such file or directory\n";
    assert.deepEqual(parseWallpaperList(text), []);
});

test("parseWallpaperList handles a missing/empty listing", () => {
    assert.deepEqual(parseWallpaperList(""), []);
    assert.deepEqual(parseWallpaperList(undefined), []);
});

test("clamp bounds both directions", () => {
    assert.equal(clamp(5, 0, 1), 1);
    assert.equal(clamp(-5, 0, 1), 0);
    assert.equal(clamp(0.5, 0, 1), 0.5);
});

test("scale fraction round-trips across the 0.8-2.5 range", () => {
    assert.equal(scaleFromFraction(0), 0.8);
    assert.equal(scaleFromFraction(1), 2.5);
    assert.equal(Math.round(fractionFromScale(1.65) * 100) / 100, 0.5);
});

test("transparency fraction is just a clamp to [0,1]", () => {
    assert.equal(transparencyFromFraction(1.5), 1);
    assert.equal(transparencyFromFraction(-1), 0);
});

test("moveGridIndex walks a single row of 4 palettes left/right, wrapping", () => {
    assert.equal(moveGridIndex(0, "l", 4, 4), 1);
    assert.equal(moveGridIndex(3, "l", 4, 4), 0, "l wraps past the last column");
    assert.equal(moveGridIndex(0, "h", 4, 4), 3, "h wraps past the first column");
});

test("moveGridIndex wraps j/k on a single-row grid back to itself", () => {
    // 4 items, 4 columns: there is only one row, so j/k have nowhere else to
    // go and must not throw or fall outside the model.
    assert.equal(moveGridIndex(1, "j", 4, 4), 1);
    assert.equal(moveGridIndex(1, "k", 4, 4), 1);
});

test("moveGridIndex moves a full row at a time on a taller grid", () => {
    // 6 items, 2 columns: two full rows and a partial third.
    assert.equal(moveGridIndex(0, "j", 6, 2), 2);
    assert.equal(moveGridIndex(0, "k", 6, 2), 4, "k wraps to the last row");
});

test("moveGridIndex on an empty model is a no-op", () => {
    assert.equal(moveGridIndex(0, "l", 0, 4), 0);
});

test("moveGridIndex ignores an unrecognised key", () => {
    assert.equal(moveGridIndex(2, "x", 4, 4), 2);
});
