pragma Singleton
// Notify — the shell's single notification hub. It IS the freedesktop.org
// notification daemon (org.freedesktop.Notifications), replacing mako: every
// `notify-send`, app notification, and `hyprctl notify`-style shell message
// flows through here. It renders nothing itself — Toasts draws the live queue,
// NotificationCenter draws the persisted history — but it owns:
//
//   items    live on-screen toasts (auto-expiring, or sticky when critical)
//   history  capped, persisted metadata log (survives restarts, via Store)
//   dnd      do-not-disturb: suppress toasts (still logged to history)
//
// Internal shell feedback still calls `Notify.send(...)`; it joins the same
// pipeline as real notifications, so history and DND cover it too.
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import "."   // Store, Config

Singleton {
    id: root

    // Live toasts: [{ id, serverId, appName, appIcon, summary, body, urgency,
    //                 level, actions:[{id,text}], time, _n }]. `_n` is the live
    // Notification handle (null for internal sends), used to invoke/dismiss.
    property var items: []
    // Persisted history (metadata only — no `_n`), newest first, capped.
    property var history: []
    // Do-not-disturb: no toasts (history still records everything).
    property bool dnd: false
    // Whether the history panel (NotificationCenter) is open. Owned here so the
    // bar bell and the IPC/keybind toggle share one source of truth.
    property bool historyOpen: false

    readonly property int _ttlMs: 4500
    readonly property int _maxHistory: 100
    property int _seq: 0

    // Persisted DND + history, shared file so it survives config reloads/restarts.
    Store {
        id: store
        name: "notifications"
        defaults: ({ dnd: false, history: [] })
        onChanged: root._hydrate()
    }
    Component.onCompleted: root._hydrate()
    function _hydrate() {
        root.dnd = !!store.get("dnd");
        root.history = store.get("history") || [];
    }

    // The daemon. Owning the DBus name requires no other server (mako) running.
    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true

        onNotification: (n) => {
            n.tracked = true;   // retain past the signal, so actions stay callable
            const rec = {
                id: ++root._seq,
                serverId: n.id,
                appName: n.appName || "",
                appIcon: n.appIcon || "",
                summary: n.summary || "",
                body: n.body || "",
                urgency: root._urgencyName(n.urgency),
                level: n.urgency === NotificationUrgency.Critical ? "error" : "info",
                actions: (n.actions || []).map(a => ({ id: a.identifier, text: a.text })),
                // Transient hint (notify-send --transient): show once, never log.
                transient: !!n.transient,
                time: Date.now(),
                _n: n
            };
            // When the server/app closes it, drop our toast — and stop us from
            // later dereferencing the (now destroyed) Notification object.
            n.closed.connect(() => root._drop(rec.id));
            root._ingest(rec);
        }
    }

    function _urgencyName(u) {
        return u === NotificationUrgency.Critical ? "critical"
             : u === NotificationUrgency.Low ? "low" : "normal";
    }

    // Internal/shell feedback (Dofus swaps, IPC, hyprland) → same pipeline.
    // level ∈ "info" | "success" | "error"; transient=true shows once but is
    // never written to history (fire-and-forget feedback, e.g. "launch enabled").
    function send(summary, body, level, transient) {
        root._ingest({
            id: ++root._seq, serverId: -1, appName: "shell", appIcon: "",
            summary: summary || "", body: body || "",
            urgency: level === "error" ? "critical" : "normal",
            level: level || "info", actions: [], transient: !!transient,
            time: Date.now(), _n: null
        });
    }

    // Route a record to the toast queue (unless DND; critical always shows and
    // never auto-expires) and to history — except transient records, which are
    // feedback-only and deliberately left out of the log.
    function _ingest(rec) {
        if (!rec.transient) {
            const meta = Object.assign({}, rec); delete meta._n;
            root.history = [meta].concat(root.history).slice(0, root._maxHistory);
            root._persist();
        }

        if (root.dnd && rec.urgency !== "critical") return;
        root.items = root.items.concat([rec]);
        // Sticky only for real critical notifications; transient feedback (even
        // error-level) is always ephemeral and auto-expires.
        if (rec.urgency !== "critical" || rec.transient)
            _expire.createObject(root, { rid: rec.id });
    }

    function _persist() { store.set({ dnd: root.dnd, history: root.history }); }

    // Remove a toast from the queue (no client-side close). The `closed` signal
    // and our own dismiss both funnel here.
    function _drop(rid) { root.items = root.items.filter(t => t.id !== rid); }

    // Dismiss a live toast (and close the client notification if it's a real one).
    // Guarded: a real notification may already be gone (destroyed C++ object).
    function dismiss(rid) {
        const rec = (root.items || []).find(t => t.id === rid);
        if (rec && rec._n) { try { rec._n.dismiss(); } catch (e) {} }
        root._drop(rid);
    }
    function dismissAll() {
        for (const rec of root.items) if (rec._n) { try { rec._n.dismiss(); } catch (e) {} }
        root.items = [];
    }

    // Invoke one of a live notification's actions (buttons in the toast).
    function invokeAction(rid, actionId) {
        const rec = (root.items || []).find(t => t.id === rid);
        if (!rec || !rec._n) return;
        try {
            const a = (rec._n.actions || []).find(x => x.identifier === actionId);
            if (a) a.invoke();
        } catch (e) {}
        root.dismiss(rid);
    }

    function toggleDnd() { root.dnd = !root.dnd; root._persist(); }
    function clearHistory() { root.history = []; root._persist(); }

    function toggleHistory() { root.historyOpen = !root.historyOpen; }
    function showHistory() { root.historyOpen = true; }
    function hideHistory() { root.historyOpen = false; }

    // One self-destructing timer per non-critical toast (independent lifetimes).
    Component {
        id: _expire
        Timer {
            property int rid
            interval: root._ttlMs; running: true; repeat: false
            onTriggered: { root.dismiss(rid); destroy(); }
        }
    }

    // qs -c quantumfate ipc call notify <fn>
    IpcHandler {
        target: "notify"
        // Push a shell message into the same pipeline as app notifications.
        function send(summary: string, body: string): void { root.send(summary, body, "info"); }
        function success(summary: string, body: string): void { root.send(summary, body, "success"); }
        function error(summary: string, body: string): void { root.send(summary, body, "error"); }
        // Transient feedback: shows once, never lands in history (e.g. the Dofus
        // "launch enabled" toast). The hyprland notification wrapper uses this.
        function feedback(summary: string, body: string): void { root.send(summary, body, "info", true); }
        // Level-aware transient toast (text + "info"/"success"/"error"), for the
        // hyprland notify wrapper that only carries a message and a level.
        function toast(text: string, level: string): void { root.send(text, "", level || "info", true); }
        // Toggle do-not-disturb; returns the new state.
        function dnd(): string { root.toggleDnd(); return root.dnd ? "on" : "off"; }
        function clear(): void { root.clearHistory(); }
        // Number of history entries — handy for status scripts.
        function count(): string { return String((root.history || []).length); }
    }
}
