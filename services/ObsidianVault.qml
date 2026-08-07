pragma Singleton
// ObsidianVault — read-only domain view over the obsidian tag store
// ($XDG_STATE_HOME/obsidian/tags.json) plus the note-creation actions the shell
// triggers. The vault is authoritative and obsidian_vault.py is the ONLY writer;
// this is a projection for the UI (the DofusState pattern, read-only).
//
// The store file carries: notes, tags (kind leaf/idx/meta_idx), topics and the
// derived `tree`. See quickshell/docs/obsidian-vault-manifest.md for the schema.
//
//   qs -c quantumfate ipc call obsidian status | tree | create | ensure | reload
import Quickshell
import Quickshell.Io
import QtQuick
import "."

Singleton {
    id: root

    // The tag store written by `obsidian_vault.py sync`. watchChanges keeps us
    // live when the script rebuilds it (post-create, or an external sync).
    Store {
        id: store
        name: "obsidian/tags"
        onChanged: root.changed()
    }
    // Shell-only UI prefs; never touches the vault or its tag store.
    Store {
        id: ui
        name: "obsidian/ui"
        defaults: ({ lastTopic: "", openOnCreate: false })
    }

    signal changed()

    readonly property bool fresh: !!store.get("generated")
    readonly property int noteCount: store.get("note_count") ?? 0
    readonly property int topicCount: store.get("topic_count") ?? 0
    readonly property string generated: store.get("generated") ?? ""
    readonly property string vault: store.get("vault") ?? ""
    readonly property var topics: store.data.topics ?? ({})
    readonly property var tree: store.data.tree ?? ({})

    // Last topic the create form used, so the next capture starts there.
    readonly property string lastTopic: ui.get("lastTopic") ?? ""
    function setLastTopic(t) { ui.set({ lastTopic: (t || "").trim() }); }

    // Whether a created note should open in Obsidian (the create form's toggle).
    readonly property bool openOnCreate: ui.get("openOnCreate") === true
    function setOpenOnCreate(v) { ui.set({ openOnCreate: !!v }); }

    // All known topic paths, sorted — the completion source for the create form.
    function topicPaths() {
        return Object.keys(root.topics).sort();
    }

    // Index-chain state for a topic path. For every ancestor segment AND the
    // topic itself: the kind of index note the script would ensure (ancestors →
    // meta_idx, the topic itself → idx) and whether it already exists, is a bare
    // stub, or is missing entirely. Read-only mirror of obsidian_vault.py's
    // plan_topic, so the form can preview "what will be created".
    function chainInfo(topic) {
        const parts = (topic || "").trim().split("/").filter(p => p.length > 0);
        const out = [];
        for (let d = 1; d <= parts.length; d++) {
            const path = parts.slice(0, d).join("/");
            const info = root.topics[path];
            const kind = d === parts.length ? "idx" : "meta_idx";
            let state = "create";
            let note = "";
            if (info) {
                const have = kind === "idx" ? info.idx_note : info.meta_idx_note;
                if (have) { state = "exists"; note = have; }
                else if (info.title) { state = "stub"; note = info.title; }
            }
            out.push({ path, kind, state, note });
        }
        return out;
    }

    // Indented rendering of the store tree (reactive; used by IPC `tree`).
    function treeText() {
        const lines = [];
        const walk = (node, depth) => {
            const keys = Object.keys(node || {}).sort();
            for (const slug of keys) {
                const n = node[slug];
                if (!n) continue;
                const idx = n.idx_note ? " [idx]" : "";
                const meta = n.meta_idx_note ? " [meta]" : "";
                const mark = idx + meta;
                const leaf = (n.leaf_count || 0) > 0 ? ` (${n.leaf_count} leaf)` : "";
                lines.push("  ".repeat(depth) + (n.title || slug) + mark + leaf);
                if (n.children) walk(n.children, depth + 1);
            }
        };
        walk(root.tree, 0);
        return lines.length > 0 ? lines.join("\n") : "(empty — run `,obsidian-cli-wrapper.sh sync`)";
    }

    function status() {
        if (!root.fresh) {
            return "store not built — run `,obsidian-cli-wrapper.sh sync`";
        }
        return [
            "vault:   " + root.vault,
            "notes:   " + root.noteCount,
            "topics:  " + root.topicCount,
            "synced:  " + root.generated,
        ].join("\n");
    }

    // ---- create / ensure -----------------------------------------------------

    property bool busy: false
    signal created(string title, bool ok)      // fired when a create finishes
    signal aborted()                           // fired when a running create is cancelled

    property string _pendingTitle: ""
    property string _pendingTopic: ""
    property string _out: ""
    property string _err: ""
    property bool _aborted: false

    Process {
        id: createProc
        stdout: StdioCollector { onStreamFinished: root._out = this.text || "" }
        stderr: StdioCollector { onStreamFinished: root._err = this.text || "" }
        onExited: (code, status) => {
            const title = root._pendingTitle;
            const topic = root._pendingTopic;
            root.busy = false;
            root._pendingTitle = "";
            root._pendingTopic = "";
            if (root._aborted) {
                root._aborted = false;
                root.aborted();
                return;
            }
            if (code === 0) {
                root.setLastTopic(topic);
                Notify.send("Note created", title, "success");
            } else {
                Notify.send("Create failed", title + " — check the note fields", "error");
                console.warn("obsidian create failed:\n" + root._out + root._err);
            }
            root.created(title, code === 0);
        }
    }

    // Start a create through the wrapper; the index chain is inferred inside the
    // script. Returns false when input is invalid or another run is in flight.
    function create(noteType, title, tag) {
        const type = (noteType || "atomic").trim();
        const t = (title || "").trim();
        const topic = (tag || "").trim();
        if (root.busy || !t || !topic) return false;
        root.busy = true;
        root._pendingTitle = t;
        root._pendingTopic = topic;
        root._out = "";
        root._err = "";
        const open = root.openOnCreate ? "--open" : "--no-open";
        createProc.command = [",obsidian-cli-wrapper.sh", "create", type, t, "--tag", topic, open];
        createProc.running = true;
        return true;
    }

    // Cancel an in-flight create/ensure. The form calls this when it closes
    // while busy; the script is killed and no notification is emitted.
    function abort() {
        if (!root.busy) return;
        root._aborted = true;
        if (createProc.running) createProc.signal(15);
        if (ensureProc.running) ensureProc.signal(15);
    }

    Process {
        id: ensureProc
        stdout: StdioCollector { onStreamFinished: root._out = this.text || "" }
        stderr: StdioCollector { onStreamFinished: root._err = this.text || "" }
        onExited: (code, status) => {
            root.busy = false;
            if (root._aborted) {
                root._aborted = false;
                root.aborted();
                return;
            }
            code === 0
                ? Notify.send("Topic ensured", "index chain up to date", "success")
                : Notify.send("Ensure failed", "", "error");
        }
    }

    function ensure(topic) {
        const t = (topic || "").trim();
        if (root.busy || !t) return false;
        root.busy = true;
        ensureProc.command = [",obsidian-cli-wrapper.sh", "ensure-topic", t];
        ensureProc.running = true;
        return true;
    }

    // qs -c quantumfate ipc call obsidian <fn>
    IpcHandler {
        target: "obsidian"
        function status(): string { return root.status(); }
        function tree(): string { return root.treeText(); }
        function create(noteType: string, title: string, tag: string): string {
            return root.create(noteType, title, tag) ? "started" : "invalid";
        }
        function ensure(topic: string): string {
            return root.ensure(topic) ? "started" : "invalid";
        }
        function reload(): void { store.reload(); }
        function lastTopic(): string { return root.lastTopic; }
        function setOpenOnCreate(openNote: string): void {
            root.setOpenOnCreate(openNote === "true" || openNote === "1");
        }
    }
}
