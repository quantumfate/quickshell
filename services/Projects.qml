pragma Singleton
// Project dashboard metadata — a thin view over a generic Store.
//
// Deliberately does not know a project's path: that stays `,proj.sh`'s alone
// (scraped from the tms config), so this file cannot disagree with it about
// where a project lives. `,proj.sh drift` is the check that catches a name
// surviving here after its tms/tmux entry is gone. See schemas/projects.schema.json.
import Quickshell
import Quickshell.Io
import QtQuick
import "."

Singleton {
    id: root

    Store {
        id: store
        name: "projects"
        defaults: ({
            projects: {
                nvim: { kind: "repo", windows: ["nvim", "zsh", "run"], study: true, priority: 0 }
            }
        })
    }

    readonly property var entries: store.data.projects ?? ({})

    function names() { return Object.keys(root.entries); }

    function get(name) { return root.entries[name]; }

    // At most one project should carry `study`; the first one wins if more do.
    readonly property string studyProject: (() => {
        for (const n of Object.keys(root.entries)) {
            if (root.entries[n] && root.entries[n].study) return n;
        }
        return "";
    })()

    function _patch(name, changes) {
        const copy = Object.assign({}, root.entries);
        copy[name] = Object.assign({}, copy[name], changes);
        store.set({ projects: copy });
    }

    // Marks `name` as the study project, clearing the flag from every other
    // entry — the schema only allows a boolean per project, not an exclusion,
    // so the "at most one" invariant is kept here rather than in the file.
    function setStudy(name) {
        if (!root.entries[name]) return;
        const copy = {};
        for (const n of Object.keys(root.entries)) {
            copy[n] = Object.assign({}, root.entries[n], { study: n === name });
        }
        store.set({ projects: copy });
    }

    function setPriority(name, priority) { root._patch(name, { priority: priority }); }
    function setKind(name, kind) { root._patch(name, { kind: kind }); }

    function remove(name) {
        if (!root.entries[name]) return;
        const copy = Object.assign({}, root.entries);
        delete copy[name];
        store.set({ projects: copy });
    }

    // ipc: qs -c quantumfate ipc call projects <fn>
    IpcHandler {
        target: "projects"
        function list(): string { return root.names().join("\n"); }
        function study(): string { return root.studyProject; }
        function setStudy(name: string): void { root.setStudy(name); }
        function reload(): void { store.reload(); }
    }
}
