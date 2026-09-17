// Store.qml's legacy-document migration gate (LEO-372 #1): migrate only when
// the target file does not exist, never merely because it reads empty — an
// empty target may be a writer mid truncate-then-rewrite, not "nothing here".
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { legacyDocument, shouldMigrate } = loadLibrary("services/StoreMigrate.js", [
    "legacyDocument", "shouldMigrate"
]);

test("legacyDocument() parses a real document", () => {
    assert.deepEqual(legacyDocument('{"shelf":{"a":1}}'), { shelf: { a: 1 } });
});

test("legacyDocument() rejects blank, empty-object, and unparsable content", () => {
    assert.equal(legacyDocument(""), null);
    assert.equal(legacyDocument("   "), null);
    assert.equal(legacyDocument("{}"), null);
    assert.equal(legacyDocument("not json"), null);
    assert.equal(legacyDocument(undefined), null);
});

test("legacyDocument() rejects a non-object document", () => {
    assert.equal(legacyDocument("[1,2,3]"), null);
    assert.equal(legacyDocument('"just a string"'), null);
});

test("shouldMigrate() is false whenever the target exists, however it reads", () => {
    // The whichkey.lua truncate-then-rewrite race: target exists and is
    // momentarily empty. Migrating here is exactly the bug LEO-372 fixes.
    assert.equal(shouldMigrate(true, '{"shelf":{"a":1}}'), false);
    assert.equal(shouldMigrate(true, ""), false);
    assert.equal(shouldMigrate(true, "{}"), false);
});

test("shouldMigrate() is true only when the target is missing AND legacy has content", () => {
    assert.equal(shouldMigrate(false, '{"shelf":{"a":1}}'), true);
    assert.equal(shouldMigrate(false, ""), false);
    assert.equal(shouldMigrate(false, "{}"), false);
    assert.equal(shouldMigrate(false, "garbage"), false);
});
