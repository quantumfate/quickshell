pragma Singleton
// Dofus class (breed) catalog — the canonical list of the 19 playable classes
// plus icon resolution. Keys are lowercase English names and double as the
// icon filenames under assets/dofus/classes/<key>.png (transparent 360px PNGs
// pulled from DofusDB's symbol art). A character's class lives in DofusState
// (keyed by character name); this singleton just turns a class key into a
// display name + icon URL, and offers "" as the always-valid "no class" value.
import Quickshell
import QtQuick

Singleton {
    id: root

    // Ordered by Ankama's breed id so the picker reads like the class-select
    // screen. `key` is both the state value and the icon basename.
    readonly property var list: [
        { key: "feca",         name: "Feca" },
        { key: "osamodas",     name: "Osamodas" },
        { key: "enutrof",      name: "Enutrof" },
        { key: "sram",         name: "Sram" },
        { key: "xelor",        name: "Xelor" },
        { key: "ecaflip",      name: "Ecaflip" },
        { key: "eniripsa",     name: "Eniripsa" },
        { key: "iop",          name: "Iop" },
        { key: "cra",          name: "Cra" },
        { key: "sadida",       name: "Sadida" },
        { key: "sacrier",      name: "Sacrier" },
        { key: "pandawa",      name: "Pandawa" },
        { key: "rogue",        name: "Rogue" },
        { key: "masqueraider", name: "Masqueraider" },
        { key: "foggernaut",   name: "Foggernaut" },
        { key: "eliotrope",    name: "Eliotrope" },
        { key: "huppermage",   name: "Huppermage" },
        { key: "ouginak",      name: "Ouginak" },
        { key: "forgelance",   name: "Forgelance" }
    ]

    // The keys only, e.g. for a picker model; "" (no class) is prepended by callers.
    readonly property var keys: list.map(c => c.key)

    readonly property var _byKey: {
        const m = ({});
        for (const c of list) m[c.key] = c;
        return m;
    }

    function has(key) { return !!(key && root._byKey[key]); }

    function nameFor(key) { return root._byKey[key] ? root._byKey[key].name : ""; }

    // Icon directory URL, resolved here (in this singleton's own context) so it
    // is stable regardless of which component calls iconFor — services/ -> ../assets.
    readonly property url _iconDir: Qt.resolvedUrl("../assets/dofus/classes/")

    // file:// URL of a class icon, or "" when the key is empty/unknown so an
    // Image bound to it simply renders nothing.
    function iconFor(key) {
        return root.has(key) ? root._iconDir + key + ".png" : "";
    }
}
