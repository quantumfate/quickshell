// Store.qml — reactive mirror of a shared JSON state file, the QML counterpart
// of hypr/lib/store.lua. Instantiate one per state file:
//
//   Store { id: store; name: "theme" }
//   store.data                       // parsed object, reactive
//   store.get("palette")             // drill into keys
//   store.set({ selected: "duo" })   // shallow-merge patch + persist
//   store.put(obj)                   // replace whole document + persist
//
// The file (in $QF_STORE/<name>.json) is the single source of truth.
// watchChanges makes external writes (Lua config, scripts) reload reactively;
// our writes bump the file so the Lua side picks them up on next access.
// A store not yet under the store directory is adopted from the legacy
// location the first time its target file is MISSING (never merely empty —
// LEO-372 #1), so moving the collection needs no tooling; the legacy file is
// then renamed to `<name>.json.migrated` so it can never be re-applied. See
// StoreMigrate.js for the pure migrate/don't-migrate decision.
import Quickshell
import Quickshell.Io
import QtQuick
import "."   // Config singleton
import "StoreMigrate.js" as StoreMigrate

Item {
    id: root

    required property string name
    readonly property string path: Config.stateDir + "/" + name + ".json"
    readonly property string legacyPath: Config.legacyStateDir + "/" + name + ".json"

    // Seed written on first run when the file is missing or empty, so a fresh
    // checkout/machine works with no manual provisioning. Leave {} for none.
    property var defaults: ({})

    property var data: ({})
    signal changed()

    function _hasDefaults() { return Object.keys(root.defaults).length > 0; }

    function get(...keys) {
        let v = root.data;
        for (const k of keys) {
            if (v === undefined || v === null) return undefined;
            v = v[k];
        }
        return v;
    }

    // Replace the whole document and persist (2-space pretty, matches Lua).
    function put(obj) {
        root.data = obj;
        file.setText(JSON.stringify(obj, null, 2) + "\n");
    }

    // Shallow-merge top-level keys, then persist.
    function set(patch) {
        put(Object.assign({}, root.data, patch));
    }

    function reload() { file.reload(); }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        // Target exists: read it as-is, migration never applies here (LEO-372
        // #1). An empty or `{}` file is either a writer mid-write (e.g. hypr's
        // whichkey.lua truncate-then-rewrite) or a genuinely empty store —
        // either way NOT evidence that the legacy document should reappear.
        onLoaded: {
            const raw = (text() || "").trim();
            let parsed;
            try {
                parsed = JSON.parse(raw || "{}");
            } catch (e) {
                console.warn("Store(" + root.name + "): bad JSON", e);
                return;
            }
            root.data = parsed;
            root.changed();
        }
        // Target missing: this is the only case migration runs from. Adopt
        // the legacy document when it holds one, else seed defaults.
        onLoadFailed: (err) => {
            const legacyRaw = legacy.text();
            if (StoreMigrate.shouldMigrate(false, legacyRaw)) {
                root.put(JSON.parse(legacyRaw.trim()));
                root._retireLegacy();
                return;
            }
            if (root._hasDefaults()) root.put(root.defaults);
            else console.warn("Store(" + root.name + "): load failed", err);
        }
    }

    FileView {
        id: legacy
        path: root.legacyPath
    }

    // Renames the legacy file out of the way after a successful migration, so
    // it can never be re-applied (mv, not FileView — FileView has no rename).
    Process { id: retireProc }
    function _retireLegacy() {
        retireProc.command = ["mv", "--", root.legacyPath, root.legacyPath + ".migrated"];
        retireProc.running = true;
    }
}
