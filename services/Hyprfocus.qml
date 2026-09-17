pragma Singleton
pragma ComponentBehavior: Bound
// Hyprfocus — the shell's view of the declaration and the mode that is on.
//
// A mode declares a desk; the compositor and the unit files converge on it.
// This singleton is the read side: which modes exist, which one is active, who
// set it, and how the desk is meant to look while it runs.
//
// It deliberately does NOT resolve a mode into a complete desk. Resolution
// already exists twice — in Lua for the compositor and in Python for the CLI —
// and a third implementation here could disagree with both about what a mode
// means, which is the divergence this whole design exists to remove. Anything
// needing a resolved desk asks `,hyprfocus resolve`; everything a bar entry
// needs is in the declaration as written.
//
//   declaration  hyprfocus.json  what every mode declares (changes rarely)
//   pointer      focus.json      which one is on (changes by the minute)
import Quickshell
import QtQuick
import "."   // Store
import "HyprfocusRead.js" as Read
import "DeclarationEdit.js" as Edit

Singleton {
    id: root

    // The whole declaration, or an empty shape until one is seeded. No
    // defaults: seeding is the CLI's job (`,hyprfocus seed`), and inventing a
    // desk here would mean the shell and the compositor disagreeing about what
    // exists the moment the real one lands.
    Store {
        id: declaration
        name: "hyprfocus"
        onChanged: root._refresh()
    }

    Store {
        id: pointer
        name: "focus"
        defaults: ({ mode: "neutral", until: null, source: null, set_at: null })
        onChanged: root._refresh()
    }

    // The raw declaration document ({ base, modes }), for pure-function
    // consumers that read it directly (e.g. modules/bar/WorkspaceSwitch.js)
    // rather than through one of this singleton's own accessors.
    readonly property var data: declaration.data ?? ({})

    // Active mode id, and the record the declaration holds for it.
    readonly property string mode: pointer.get("mode") ?? "neutral"
    property var current: ({})
    property var modes: ({})

    // Who put the desk in this mode. Absent provenance reads as manual: a
    // pointer of unknown origin is safer assumed deliberate than treated as
    // something automation may overwrite.
    readonly property string source: pointer.get("source") || "manual"
    readonly property var until: pointer.get("until") ?? null
    readonly property var setAt: pointer.get("set_at") ?? null

    // Whether a mode is actually declared. A pointer naming a mode the
    // declaration does not have is a real state — a store edited by hand, or a
    // declaration replaced under a running shell — and the bar should say so
    // rather than render a blank.
    readonly property bool known: Read.known(declaration.data, root.mode)
    readonly property bool resting: root.mode === "neutral"

    // How the desk is meant to look while this mode runs. Passed through
    // untouched by every other layer; this is the only consumer.
    readonly property var presentation: root.current.presentation ?? ({})

    Component.onCompleted: root._refresh()

    // Force the read side now. Both singletons watch the same focus.json
    // write and their refresh order is not guaranteed, so the announce seam
    // (LEO-242) calls this before it reads `current` — the declaration then
    // answers for the mode the transition is ENTERING, not the one that was.
    function refresh() { root._refresh(); }

    function _refresh() {
        root.modes = declaration.get("modes") ?? ({});
        root.current = root.modes[root.mode] ?? ({});
    }

    function label(id) { return Read.label(declaration.data, id); }
    function ids() { return Read.ids(declaration.data); }
    function withholds(id) { return Read.withholds(declaration.data, id); }

    /** Whether `withholds` is telling less than the whole story for this mode. */
    function narrows(id) { return Read.narrows(declaration.data, id); }

    // Notification routing for the active mode: the base's rules with this
    // mode's merged over them. Empty until a declaration is seeded, which the
    // daemon reads as "no routing declared" rather than as "drop everything".
    readonly property var routes: root.modes ? Read.routes(declaration.data, root.mode) : ({})

    // The panel's edit half (LEO-280): one validated, live write into the
    // declaration. Validation runs BEFORE the store is touched — a write
    // that breaks the contract is refused, not stored; an edit that lands
    // publishes through the same file both runtimes watch, no reload.
    //
    // Returns "" on success or the reason the write was refused.
    function patchMode(mode, patch) {
        const spec = (root.modes || {})[mode];
        if (!spec) return "unknown mode '" + mode + "'";
        const next = Edit.modePatch(spec, patch);
        if (next === null) return "the edit breaks the declaration's contract";
        root.declaration.set({ modes: Object.assign({}, root.modes, { [mode]: next }) });
        return "";
    }
}
