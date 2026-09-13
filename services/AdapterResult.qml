pragma Singleton
// What the last adapter run actually did.
//
// Action adapters (`,theme.sh` and friends) write `<name>.result.json` after a
// run. This reads the theme one, because that is the adapter whose honesty the
// UI depends on: a palette switch reaches nine surfaces and any of them can be
// absent on a given machine, so "applied" is a claim that has to be earned
// rather than assumed. See schemas/adapter-result.schema.json.
import Quickshell
import Quickshell.Io
import QtQuick
import "."

Singleton {
    id: root

    Store {
        id: store
        name: "theme.result"
        // A machine that has never run an apply is not an error state: it
        // reports nothing rather than an empty success.
        defaults: ({ ok: true, ts: 0, adapter: "theme", applied: [], pending: [], failed: [] })
    }

    readonly property bool ok: store.data.ok ?? true
    readonly property int ts: store.data.ts ?? 0
    readonly property string adapter: store.data.adapter ?? "theme"

    readonly property var applied: store.data.applied ?? []
    readonly property var pending: store.data.pending ?? []
    readonly property var failed: store.data.failed ?? []

    // True before any adapter has ever run. Distinct from a run that applied
    // nothing, which is a real (and suspicious) outcome.
    readonly property bool everRan: root.ts > 0

    readonly property int ageSeconds: root.everRan ? Math.max(0, Math.floor(Date.now() / 1000) - root.ts) : -1

    // What the picker shows before committing, and the System Center chip
    // after: "9 immediate · 1 next-launch". Failures are counted separately so
    // they can be coloured as failures rather than buried in a total.
    readonly property string tierSummary: {
        const parts = [];
        const immediate = root.applied.filter(e => e && e.tier === "immediate").length;
        const relaunch = root.pending.filter(e => e && e.tier === "next-launch").length;
        if (immediate) parts.push(immediate + " immediate");
        if (relaunch) parts.push(relaunch + " next-launch");
        if (root.failed.length) parts.push(root.failed.length + " failed");
        return parts.length ? parts.join(" · ") : "nothing to apply";
    }

    // The quiet chip: only what is still outstanding, named, so "restart Zen"
    // is actionable rather than a number.
    readonly property string pendingSummary: root.pending.length
        ? root.pending.length + " pending relaunch: " + root.pending.map(e => e.surface).join(", ")
        : ""

    function reasonFor(surface) {
        for (const e of root.pending) if (e && e.surface === surface) return e.reason ?? "";
        for (const e of root.failed) if (e && e.surface === surface) return e.reason ?? "";
        return "";
    }
}
