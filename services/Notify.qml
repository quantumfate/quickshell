pragma Singleton
pragma ComponentBehavior: Bound
// Notify — the shell's single notification hub. It IS the freedesktop.org
// notification daemon (org.freedesktop.Notifications), replacing mako: every
// `notify-send`, app notification, and `hyprctl notify`-style shell message
// flows through here. It renders nothing itself — Toasts draws the live queue,
// NotificationCenter draws the persisted history — but it owns:
//
//   items    live on-screen toasts (auto-expiring per policy, sticky when
//            critical or the active mood's timeout is 0)
//   history  capped, persisted metadata log (survives restarts, via Store);
//            every entry records its `route`: "shown" | "dnd" | "mood:<mode>"
//   dnd      manual do-not-disturb: suppress toasts (still logged to history)
//   moods    the active focus mood's notification policy also gates the screen
//            ("critical-only"/"none" silence toasts; history still records),
//            re-positions the queue (Toasts anchors per policy), and — when a
//            mood queues + digests — folds the buffered, suppressed work into
//            one digest toast when the mood ends
//
// Internal shell feedback still calls `Notify.send(...)`; it joins the same
// pipeline as real notifications, so history and DND cover it too.
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import "."   // Store, Focus, Hyprfocus, Config
import "NotifyRoute.js" as NotifyRoute

Singleton {
    id: root

    // Live toasts: [{ id, serverId, appName, appIcon, summary, body, urgency,
    //                 level, actions:[{id,text}], time, source, tier, _n }].
    // `_n` is the live Notification handle (null for internal sends), used to
    // invoke/dismiss. `source` is the resolved identity (NotifyRoute), kept
    // because `appName` is the sender's own claim and cannot be routed on.
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
    // Suppressed notifications buffered for the digest toast a queuing mood
    // asks for on exit (metadata only: the logs already hold the details).
    property var _queued: []
    property string _queueMood: ""

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
            // Identity, resolved through the chain rather than taken from
            // `appName`: that field is self-reported free text, so two programs
            // can claim one name and a script has none at all. Recorded now so
            // the routes a mode will key on can be written from what actually
            // arrives rather than guessed at.
            root._identify(rec, n);
            n.closed.connect(() => root._drop(rec.id));
            root._ingest(rec);
        }
    }

    // The resolved source id, the tier it resolved at, and whether that tier
    // is one the sender could choose freely. A sender that only resolves at the
    // bottom is visible in history rather than mysterious.
    function _identify(rec, n) {
        const r = NotifyRoute.source({ appName: n.appName, desktopEntry: n.desktopEntry, hints: n.hints });
        rec.source = r.id;
        rec.tier = r.tier;
        rec.trusted = r.trusted;
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
            time: Date.now(), _n: null,
            source: "hyprfocus-shell", tier: NotifyRoute.TIER.HYPRFOCUS, trusted: true
        });
    }

    // Route a record to history (every entry remembers why it did/didn't toast)
    // and, when it is not suppressed, to the live toast queue. Transient
    // records stay feedback-only and never land in the log.
    function _ingest(rec) {
        const route = root._route(rec);
        if (!rec.transient) {
            const meta = Object.assign({}, rec); delete meta._n;
            meta.route = route || "shown";
            // A mood that queues suppressed work buffers it for a digest toast
            // on exit (queue + digest_on_exit are the mood's own flags — see
            // Focus.notifications). The buffer is runtime-only, deliberately:
            // history already logged the suppressed records in full.
            // Buffered for the digest when the mood asks for one, and also
            // when a rule said `queue` outright — a verdict that names
            // queueing should queue whatever the mood happens to want.
            if (route && (Focus.notifications.queue || route === "mode:queue")) {
                root._queued = root._queued.concat([meta]);
                root._queueMood = Focus.mode;
            }
            root.history = [meta].concat(root.history).slice(0, root._maxHistory);
            root._persist();
        }

        if (route) return;
        root.items = root.items.concat([rec]);
        // Sticky for critical notifications and for moods whose policy timeout
        // is 0 (persist until dismissed); transient feedback is always
        // ephemeral and auto-expires.
        const ttl = root._ttl(rec);
        if (ttl > 0)
            _expire.createObject(root, { rid: rec.id, interval: ttl });
    }

    // Why a record is (or is not) on screen: "" (shown), "dnd" (manual DND —
    // critical still breaks through), or "mood" (the active mood's policy —
    // critical does NOT break a strict mood). The reason is recorded as each
    // history entry's `route`; only "shown" ever toasted.
    //
    // A declared rule for this notification's resolved source wins over the
    // mood's blanket policy, because it is the more specific statement: "queue
    // the sync results" should hold whether or not the mood silences
    // everything else. Only an EXPLICIT source rule applies — the declaration's
    // `default` is deliberately not consulted yet, so a desk with no
    // declaration, or one carrying only a default, behaves exactly as before.
    // The blanket policy moves across when the mode surface replaces the mood
    // panel that still owns it.
    // The verdict a declaration gives this notification's resolved source, or
    // "" when it declares none. Only an EXPLICIT source rule counts: the
    // declaration's `default` is deliberately not consulted yet, so a desk
    // with no declaration — or one carrying only a default — behaves exactly
    // as it did before. The blanket policy moves across when the mode surface
    // replaces the mood panel that still owns it.
    function _verdict(rec) {
        const rules = Hyprfocus.routes;
        if (!rules || !rec.source) return "";
        const verdict = rules[rec.source] || "";
        if (!verdict) return "";
        // Critical escalates out of silence unless the rule says otherwise. A
        // mode that hides "battery at 2%" is not reducing distraction, it is
        // withholding something that was needed.
        if (rec.urgency === "critical" && verdict !== "show" && !rules.allowCriticalSuppression) {
            return "show";
        }
        return verdict;
    }

    function _route(rec) {
        if (root.dnd && rec.urgency !== "critical") return "dnd";

        // A declared rule for this source wins over the mood's blanket policy,
        // because it is the more specific statement: "queue the sync results"
        // should hold whether or not the mood silences everything else, and an
        // explicit "show" should break through a mood that does.
        const verdict = root._verdict(rec);
        if (verdict) return verdict === "show" ? "" : "mode:" + verdict;

        const policy = Focus.notifications.policy;
        if (policy === "critical-only") return rec.urgency === "critical" ? "" : "mood";
        return policy === "none" ? "mood" : "";
    }

    // A toast's lifetime: critical ones and moods with a 0 timeout stick until
    // closed; transient feedback always auto-expires at the default ttl. In a
    // mood (always the case through `Focus.notifications`), 0 means sticky.
    function _ttl(rec) {
        if (rec.transient) return root._ttlMs;
        if (rec.urgency === "critical") return 0;
        const t = Focus.notifications.timeout;
        return (typeof t === "number" && t > 0) ? t : 0;
    }

    // Fold a finished mood's buffered work into ONE digest toast, per that
    // mood's own queue/digest_on_exit flags. Fires when the mood ends however
    // it ends — a switch away, an explicit stop, or a timed lapse.
    Connections {
        target: Focus
        function onModeChanged() { root._moodChanged(); }
    }
    function _moodChanged() {
        if (!root._queued.length || !root._queueMood) return;
        const over = !Focus.active || Focus.mode !== root._queueMood;
        if (!over) return;
        const m = Focus.policyData[root._queueMood] || {};
        const n = m.notifications || {};
        if (n.digest_on_exit) {
            const names = [...new Set(root._queued.map(q => q.appName || "notification"))];
            const label = names.slice(0, 3).join(", ") + (names.length > 3 ? ", \u2026" : "");
            const count = root._queued.length + " notification" + (root._queued.length === 1 ? "" : "s");
            root.send(count + " while " + (m.name || root._queueMood) + " was on", label, "info");
        }
        root._queued = [];
        root._queueMood = "";
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

    // One self-destructing timer per auto-expiring toast (independent lifetimes).
    // `interval` is injected at creation from the policy ttl (see _ttl).
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
