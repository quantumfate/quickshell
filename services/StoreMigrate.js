.pragma library
// Pure decision logic behind Store.qml's legacy-document migration
// (LEO-372 #1). Kept separate from the QML so the "when do we migrate" call
// is unit-testable against plain strings — see tests/storemigrate.test.js.
//
// The bug this fixes: a writer that truncates-then-rewrites its target file
// (hypr's whichkey.lua `dump`) leaves the target briefly empty. Store used to
// treat "empty" as "nothing here yet" and pull the legacy document back over
// it, so the truncate-rewrite race made the legacy content reappear forever.
// The fix is narrower: migrate a legacy document ONLY when the target file
// does not exist at all. An existing-but-empty target is either a writer
// mid-write or a genuinely empty store, and both must be left alone.

/**
 * Whether `legacyRaw` holds a usable document to migrate: non-blank, valid
 * JSON, and not an empty object. Returns the parsed document, or null when
 * there is nothing worth migrating.
 */
function legacyDocument(legacyRaw) {
    const raw = (legacyRaw || "").trim();
    if (raw === "" || raw === "{}") return null;
    let parsed;
    try {
        parsed = JSON.parse(raw);
    } catch (e) {
        return null;
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
    if (Object.keys(parsed).length === 0) return null;
    return parsed;
}

/**
 * Migration only ever runs off a missing target file (Store.qml's
 * `onLoadFailed`); an existing target — empty, `{}`, or populated — is never
 * touched here, so this is the one gate both branches (legacy present vs.
 * defaults-only) share.
 */
function shouldMigrate(targetExists, legacyRaw) {
    return !targetExists && legacyDocument(legacyRaw) !== null;
}
