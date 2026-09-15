pragma Singleton
// Theme packs — the shell's runtime read of the pack format (LEO-289).
//
// The packs live in assets/packs/ as data, shipped alongside the config
// (deployment symlinks the whole config root, so `../assets/packs/…` always
// resolves next to shell.qml). Each is parsed when it loads; a pack that
// fails its own contract is dropped rather than half-rendered — a pack is
// data validated on install, and the desk keeps the palettes it can trust.
//
// ThemePacks.js derives the semantic roles; this singleton only administers
// the documents and answers queries. Theme.qml binds `palettes` here, so a
// new variant in a pack file is data the shell speaks without a change to
// the shell.
import Quickshell
import Quickshell.Io
import QtQuick
import "."
import "ThemePacks.js" as Packs

Singleton {
    id: root

    // The shipped pack families. The directory ships with the config, so a
    // family exists when its file does; a name here without a file reads as
    // nothing.
    readonly property var families: ["catppuccin", "gruvbox"]

    // Pack name -> parsed document, one entry per readable file.
    property var packs: ({})
    readonly property bool settled: Object.keys(root.packs).length > 0

    // The trusted set: loaded documents whose own contract holds. An invalid
    // pack is dropped, not half-rendered.
    function trusted() {
        return root.families
            .map(name => root.packs[name])
            .filter(p => p && Packs.lint(p).length === 0);
    }

    // The whole variant vocabulary the theme switch speaks: variant id ->
    // derived table, across every trusted pack.
    readonly property var palettes: {
        const merged = {};
        for (const pack of root.trusted()) {
            for (const id in Packs.variants(pack)) {
                const table = Packs.palette(pack, id);
                if (table) merged[id] = table;
            }
        }
        return merged;
    }

    // The pack a variant id belongs to. Identifiers are unique across
    // families because a pack's variants never collide with another's.
    function packOf(variantId) {
        for (const pack of root.trusted()) {
            if (Packs.palette(pack, variantId)) return pack;
        }
        return null;
    }

    // The accent colour a mode's accent_role names, resolved per the owning
    // pack's accent map. Never fails: unknown reads as mauve.
    function accentHue(variantId, role) {
        const pack = root.packOf(variantId);
        return pack ? Packs.accentHue(pack, variantId, role) : null;
    }

    // The variant that answers a need for the other half of the day/night
    // cycle, through the pack the variant belongs to.
    function counterpart(variantId, kind) {
        const pack = root.packOf(variantId);
        return pack ? Packs.counterpart(pack, variantId, kind) : null;
    }

    function kindOf(variantId) {
        const pack = root.packOf(variantId);
        if (!pack) return null;
        const variant = Packs.variants(pack)[variantId];
        return variant ? variant.kind : null;
    }

    function _held(name, parsed) {
        root.packs = Object.assign({}, root.packs, { [name]: parsed });
    }

    Reader { id: reader }
    component Reader: Item {
        Repeater {
            model: root.families
            delegate: FileView {
                required property string modelData
                path: Qt.resolvedUrl("../assets/packs/" + modelData + ".json")
                watchChanges: false
                onLoaded: {
                    try {
                        const raw = (text() || "").trim();
                        root._held(modelData, JSON.parse(raw || "{}"));
                    } catch (e) { console.warn("packs: unreadable JSON " + modelData); }
                }
                onLoadFailed: () => console.warn("packs: missing family " + modelData)
            }
        }
    }
}
