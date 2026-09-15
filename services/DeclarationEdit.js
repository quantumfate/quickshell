.pragma library

// The mode panel's edit half (LEO-280): declaration writes done the way the
// shell writes everything else, with one gate added — the write is validated
// against the declaration's contract before it lands, so a typo never
// becomes a desk the compositor resolves into something else. Editing is
// live: the store is authoritative and both runtimes watch it, so a valid
// edit applies with no reload.
//
// The gate is deliberately narrow. It covers the fields the panel edits —
// the presentation block and its leases — with exactly the checks the
// shipped schema carries for them; a full JSON-schema engine would be a
// second answer to what the schema already says.

/** A declaration id: lowercase alphanumeric with dashes, exactly as the schema's $defs/id. */
function validId(value) {
    return /^[a-z0-9][a-z0-9-]*$/.test(value);
}

/**
 * The presentation block a mode would carry after applying `patch`, or null
 * when it breaks the contract: the panel refuses the write rather than
 * storing a defect. An absent patch rides through untouched.
 */
function presentation(edited, patch) {
    const out = Object.assign({}, edited || {}, patch || {});
    if (out.palette !== undefined && out.palette !== "") {
        if (!validId(out.palette)) return null;
    }
    if (out.wallpaper !== undefined && String(out.wallpaper).length > 256) return null;
    return out;
}

/**
 * The one patch the editor writes: { presentation }-shaped, whole-field (the
 * panel renders complete values, it never patches fragments). Returns the
 * resolved patch merged onto the mode's record, or null when a field is
 * outside the panel's authority — the declaration is edited where it is
 * understood, and scenes/binding tricks are not a panel row.
 */
function modePatch(spec, presentationPatch) {
    const next = presentation(spec && spec.presentation, presentationPatch);
    if (next === null) return null;
    return Object.assign({}, spec || {}, { presentation: next });
}
