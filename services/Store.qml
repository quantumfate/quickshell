// Store.qml — reactive mirror of a shared JSON state file, the QML counterpart
// of hypr/lib/store.lua. Instantiate one per state file:
//
//   Store { id: team; name: "dofus/team" }
//   team.data                       // parsed object, reactive
//   team.get("teams", "pioneer")    // drill into keys
//   team.set({ selected: "duo" })   // shallow-merge patch + persist
//   team.put(obj)                   // replace whole document + persist
//
// The file (in $XDG_STATE_HOME/<name>.json) is the single source of truth.
// watchChanges makes external writes (Lua config, scripts) reload reactively;
// our writes bump the file so the Lua side picks them up on next access.
import Quickshell
import Quickshell.Io
import QtQuick
import "."   // Config singleton

Item {
    id: root

    required property string name
    readonly property string path: Config.stateDir + "/" + name + ".json"

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
        onLoaded: {
            const raw = (text() || "").trim();
            if ((raw === "" || raw === "{}") && root._hasDefaults()) {
                root.put(root.defaults); // seed an empty/blank file
                return;
            }
            try {
                root.data = JSON.parse(raw || "{}");
                root.changed();
            } catch (e) {
                console.warn("Store(" + root.name + "): bad JSON", e);
            }
        }
        // Missing file: seed defaults (which creates it), else just warn.
        onLoadFailed: (err) => {
            if (root._hasDefaults()) root.put(root.defaults);
            else console.warn("Store(" + root.name + "): load failed", err);
        }
    }
}
