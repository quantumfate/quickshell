pragma Singleton
// Notify — a tiny in-shell feedback bus. Any code calls `Notify.send(...)`;
// the Toasts widget (modules/bar/Toasts.qml) renders the queue and this service
// auto-expires each entry. Self-contained (not the system mako pipeline), so
// feedback is themed and lives right under the bar.
import Quickshell
import QtQuick

Singleton {
    id: root

    // Live toast list; each: { id:int, summary:string, body:string, level:string }.
    // level ∈ "info" | "success" | "error" (drives the Toasts accent color).
    property var items: []

    property int _seq: 0
    readonly property int _ttlMs: 3200

    // Push a toast and schedule its removal.
    function send(summary, body, level) {
        const id = ++root._seq;
        root.items = root.items.concat([{ id, summary, body: body || "", level: level || "info" }]);
        _expire.createObject(root, { toastId: id });
    }

    function _remove(id) { root.items = root.items.filter(t => t.id !== id); }

    // One self-destructing timer per toast, so lifetimes are independent.
    Component {
        id: _expire
        Timer {
            property int toastId
            interval: root._ttlMs; running: true; repeat: false
            onTriggered: { root._remove(toastId); destroy(); }
        }
    }
}
