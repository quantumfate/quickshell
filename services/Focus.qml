pragma Singleton
// Focus mode: a Store plus the enforcement seam, not the UI.
//
// A mood is a visual operating state — "how the desk feels" — not merely a
// notification switch. `mode` names one of six moods (see `moods` below);
// `neutral` is the resting state every desk starts in. Switching moods is a
// single `store.set`, exactly like Theme's palette switch, and everything
// that reads `Focus.mode`/`Focus.current` reacts on its own — see Theme.qml's
// `accent`/`surfaceAlpha`, which are bound to `Focus.accentRole` and
// `Focus.surfaceAlpha` rather than recomputed by hand.
//
// Firm semantics carry over unchanged from the old off/focus binary: refuse,
// with an explicit override, never tear down a session already running.
// `canLaunch`/`blockReason` are read at DISPATCH time by whatever launches a
// media browser or a game (an IPC call from a script, not a compiled-in bind
// check), so switching moods needs no Hyprland reload — the next launch
// attempt just sees the new mood. A mood does not block launching *into*
// itself: `game` never blocks a game launch, `media` never blocks a media
// launch. Every other non-neutral mood blocks both, same as the old "focus"
// session did.
//
// This file owns the data and the yes/no; it does not enforce anything by
// itself, and it does not resolve wallpapers — `,theme.sh mood-wallpaper`
// does that from `mode` alone. See ARCHITECTURE.md and the task report for
// what still needs to call into it (media browser + game launcher scripts,
// DND, the media workspace's reachability) — none of those are this repo's
// files.
import Quickshell
import Quickshell.Io
import QtQuick
import "."

Singleton {
    id: root

    Store {
        id: store
        name: "focus"
        defaults: ({ mode: "neutral", until: null })
    }

    readonly property string mode: store.get("mode") ?? "neutral"
    readonly property var until: store.get("until") ?? null

    // The six moods. Accent is named as a *role* on the active palette
    // (Theme.c.<role>), never a literal colour: the palette stays the source
    // of truth and a mood only picks which of its roles takes the spotlight,
    // so a palette swap still recolours every mood correctly. surfaceAlpha is
    // the one dial each mood turns on the shared card material (see
    // Theme.qml's `surfaceAlpha` map) — paper, not glass, and lower than the
    // pre-mood baseline on purpose. Wallpaper is deliberately absent here:
    // `,theme.sh mood-wallpaper` resolves mood -> wallpaper on its own so this
    // table does not duplicate that mapping.
    readonly property var moods: ({
        neutral: {
            name: "Neutral", accentRole: "lavender", surfaceAlpha: 0.84,
            density: "comfortable", motionEnergy: "base", barAutohide: false,
            notifications: { policy: "all", position: "top-right", timeout: 6000, queue: false, digestOnExit: false }
        },
        deep: {
            name: "Deep work", accentRole: "blue", surfaceAlpha: 0.94,
            density: "compact", motionEnergy: "instant", barAutohide: true,
            notifications: { policy: "critical-only", position: "top-right", timeout: 0, queue: true, digestOnExit: true }
        },
        chores: {
            name: "Chores", accentRole: "peach", surfaceAlpha: 0.80,
            density: "dense", motionEnergy: "fast", barAutohide: false,
            notifications: { policy: "all", position: "top-right", timeout: 4000, queue: false, digestOnExit: false }
        },
        reflect: {
            name: "Reflect", accentRole: "mauve", surfaceAlpha: 0.70,
            density: "airy", motionEnergy: "slow", barAutohide: false,
            notifications: { policy: "none", position: "top-right", timeout: 0, queue: true, digestOnExit: true }
        },
        game: {
            name: "Gaming", accentRole: "green", surfaceAlpha: 0.96,
            density: "compact", motionEnergy: "instant", barAutohide: false,
            notifications: { policy: "none", position: "top-right", timeout: 0, queue: true, digestOnExit: false }
        },
        media: {
            name: "Media", accentRole: "pink", surfaceAlpha: 0.62,
            density: "airy", motionEnergy: "ambient", barAutohide: true,
            notifications: { policy: "critical-only", position: "bottom-right", timeout: 0, queue: false, digestOnExit: false }
        }
    })

    // The active mood's full definition. Falls back to neutral so a bad/stale
    // `mode` in the file (or mid-migration) never leaves a reader with
    // `undefined.accentRole`.
    readonly property var current: root.moods[root.mode] ?? root.moods.neutral

    readonly property string accentRole: root.current.accentRole
    readonly property real surfaceAlpha: root.current.surfaceAlpha
    readonly property string density: root.current.density
    readonly property string motionEnergy: root.current.motionEnergy
    readonly property bool barAutohide: root.current.barAutohide
    readonly property var notifications: root.current.notifications

    // Live even past `until`: a stale non-neutral mood that nothing has
    // cleared yet should stop blocking (and read as neutral) on its own,
    // rather than wait for the next explicit `stop()`.
    readonly property bool active: root.mode !== "neutral" &&
        (root.until === null || Date.now() < Date.parse(root.until))

    // Kinds firm focus blocks. Anything else (a terminal, an editor) is
    // untouched — this takes options away, it does not lock the desk down.
    readonly property var blockedKinds: (["media", "game"])

    // A mood never blocks launching into itself: entering `game` is how you
    // start gaming, so it cannot also refuse the game launch that got you
    // there. Every other active mood blocks both kinds, same as the old
    // binary "focus" session did.
    function canLaunch(kind) {
        return !(root.active && root.mode !== kind && root.blockedKinds.indexOf(kind) >= 0);
    }

    function blockReason(kind) {
        if (root.canLaunch(kind)) return "";
        const until = root.until ? (" until " + root.until) : "";
        return root.current.name + " is on" + until + " — this is blocked while it runs";
    }

    // Enter a mood. `minutes` <= 0 (or omitted) means open-ended (only
    // `stop()`, or another `set()`, ends it).
    function set(mode, minutes) {
        if (!root.moods[mode]) return;
        const until = (minutes && minutes > 0)
            ? new Date(Date.now() + minutes * 60000).toISOString()
            : null;
        store.set({ mode: mode, until: until });
    }

    // The explicit override: back to the resting state. Also what a lapsed
    // timed mood settles to on its own via `active`.
    function stop() { store.set({ mode: "neutral", until: null }); }

    // ipc: qs -c quantumfate ipc call focus <fn>
    IpcHandler {
        target: "focus"
        function status(): string {
            return root.mode + (root.until ? (" until " + root.until) : "");
        }
        // Enter a mood: `ipc call focus set deep 90` (90 minutes), or
        // `ipc call focus set deep` for open-ended.
        function set(mode: string, minutes: int): void { root.set(mode, minutes); }
        function stop(): void { root.stop(); }
        // "yes" / "no: <reason>" — a launcher script greps the first word.
        function canLaunch(kind: string): string {
            return root.canLaunch(kind) ? "yes" : ("no: " + root.blockReason(kind));
        }
        function reload(): void { store.reload(); }
    }
}
