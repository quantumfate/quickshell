pragma Singleton
// Scene vetoes — the shell's surface of a resource's refusal (LEO-256).
//
// The enforced seam (bin/,scene-apply.sh) honours a unit's own refuse-to-stop
// window in the unit's own words, and writes what it held into
// scene-policy/last.json, once per apply. This singleton watches that file
// and raises each veto the desk has not surfaced yet — deduplicated by the
// registry of shown vetoes it keeps in its own store — so a unit that
// refuses repeatedly lands in the log (LEO-241's workspace reads
// log.jsonl) rather than as a toast the shell re-fires forever. A veto is
// not a failure: the transition completes without the resource, per the
// protocol.
import Quickshell
import Quickshell.Io
import QtQuick
import "."

Singleton {
    id: root

    // The vetoes the desk has already surfaced: unit -> the veto's ts. A new
    // window from the same unit on a later apply is a NEW refusal, and is
    // surfaced again — refusal is only silent when it repeats identical.
    Store {
        id: registry
        name: "scene-veto"
        defaults: ({ seen: {} })
        onChanged: root._hydrate()
    }
    Component.onCompleted: root._hydrate()
    property var _seen: ({})
    function _hydrate() { root._seen = registry.get("seen") ?? {}; }

    // What the last apply held, watched like theme.result.json is.
    property var last: ({})

    readonly property string _path: Config.stateDir + "/scene-policy/last.json"
    FileView {
        id: lastFile
        path: root._path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.last = JSON.parse((text() || "{}"));
                root._surface();
            } catch (e) { console.warn("scene-veto: bad last.json", e); }
        }
        onLoadFailed: () => {}   // no apply yet; nothing to surface
    }

    function _surface() {
        for (const v of root.last.vetoes || []) {
            if (!v.unit) continue;
            const key = v.unit;
            const ts = root.last.ts ?? 0;
            if (root._seen[key] && root._seen[key] >= ts) continue;   // already surfaced
            // A veto is the resource speaking for itself once — transient (no
            // history entry): it answered a question the desk asked it.
            Notify.send(key, "the unit refused to stop: " + (v.reason || "no reason given"), "info", true);
            root._seen = Object.assign({}, root._seen, { [key]: ts });
            registry.set({ seen: root._seen });
        }
    }
}
