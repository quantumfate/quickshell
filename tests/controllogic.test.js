// The Control Centre's pure logic: wallpaper listing off `ls`, and the
// scale/transparency slider <-> dial-value mapping.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { parseWallpaperList, clamp, scaleFromFraction, fractionFromScale, transparencyFromFraction } =
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
