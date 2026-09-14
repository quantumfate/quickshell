pragma Singleton
// Focus mode: a Store plus the enforcement seam, not the UI.
//
// Two stores live here. `focus.json` is the ACTIVE state — `{ mode, until }` —
// the pointer to the mood the desk is in right now. `mood-policy.json` is the
// DEFINITIONAL store: what each of the six moods *means* (accent role, surface
// alpha, notifications, launches, background work, scene reachability). The
// policy store is the source of truth this singleton reads and writes through
// `patchMood`; the shipped default (assets/mood-policy.default.json) is pinned
// identical to the `policyDefaults` literal below by the lockstep test, and the
// panel/editor writes to the same file the Hyprland event manager and the
// launcher scripts read. A mood is therefore one edit away in a JSON file, and
// every runtime reads the same policy.
//
// `mode` names one of the declared moods (see `policyDefaults`); `neutral` is the resting
// state every desk starts in. Switching moods is a single `set()` — exactly like
// Theme's palette switch — and everything that reads `Focus.mode` /
// `Focus.current` reacts on its own: Theme.qml binds its `accent` and
// `surfaceAlpha` to `Focus.accentRole`/`Focus.surfaceAlpha`, which are plain
// bindings over the store, so an edit to mood-policy.json repaints the shell
// and re-gates Notify with no reload.
//
// Firm semantics carry over unchanged from the old off/focus binary: refuse,
// with an explicit override, never tear down a session already running.
// `canLaunch`/`blockReason` are read at DISPATCH time by whatever launches a
// media browser or a game (an IPC call from a script, not a compiled-in bind
// check), so switching moods needs no Hyprland reload — the next launch
// attempt just sees the new mood. The active mood's launch policy is the store's
// `launches` table: `soft` warns and lets through, `firm`/`hard` refuse; a mood
// never blocks launching *into* itself (`game` never blocks a game launch,
// `media` never blocks a media launch), and neutral never blocks anything.
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

    // Deliberately NOT read-exclusive during hydration: the first store read
    // below must not be gated, but the scene-apply trigger only fires once the
    // stores settled (a first-run seed must not touch systemd).
    property bool _hydrated: false
    Component.onCompleted: root._hydrated = true

    Store {
        id: stateStore
        name: "focus"
        defaults: ({ mode: "neutral", until: null })
    }

    readonly property string mode: stateStore.get("mode") ?? "neutral"
    readonly property var until: stateStore.get("until") ?? null

    // The definitional per-mood policy, in the store's snake_case shape. This
    // literal IS assets/mood-policy.default.json (the lockstep test pins them
    // identical) and it seeds the state file on first run — so a fresh machine
    // and a hand-migrated one agree on what "deep work" means. The palette
    // accent is named as a *role* on the active palette (Theme.c.<role>), never
    // a literal colour; `surface_alpha` is the one dial each mood turns on the
    // shared card material (see Theme.qml's `surfaceAlpha` map) — paper, not
    // glass. Wallpaper is deliberately absent: `,theme.sh mood-wallpaper`
    // resolves mood -> wallpaper on its own so this table does not duplicate it.
    readonly property var policyDefaults: ({
        moods: {
            neutral: {
                name: "Neutral", accent_role: "lavender", surface_alpha: 0.84,
                density: "comfortable", motion_energy: "base", bar_autohide: false,
                notifications: { policy: "all", position: "top-right", timeout: 6000, queue: false, digest_on_exit: false },
                launches: { aggression: "soft", block: [], override: false },
                background: { policy: "allow", allow: ["*"], defer: [], prevent: [] },
                scenes: {}
            },
            work: {
                name: "Work", accent_role: "blue", surface_alpha: 0.94,
                density: "compact", motion_energy: "instant", bar_autohide: true,
                notifications: { policy: "critical-only", position: "top-right", timeout: 0, queue: true, digest_on_exit: true },
                launches: { aggression: "firm", block: ["media", "game"], override: true },
                background: { policy: "allow", allow: ["*"], defer: [], prevent: [] },
                scenes: { gaming: "blocked", media: "blocked" }
            },
            study: {
                name: "Study", accent_role: "mauve", surface_alpha: 0.94,
                density: "compact", motion_energy: "instant", bar_autohide: true,
                notifications: { policy: "critical-only", position: "top-right", timeout: 0, queue: true, digest_on_exit: true },
                launches: { aggression: "firm", block: ["media", "game"], override: true },
                background: { policy: "allow", allow: ["*"], defer: [], prevent: [] },
                scenes: { gaming: "blocked", media: "blocked" }
            },
            gaming: {
                name: "Gaming", accent_role: "green", surface_alpha: 0.96,
                density: "compact", motion_energy: "instant", bar_autohide: false,
                notifications: { policy: "none", position: "top-right", timeout: 0, queue: true, digest_on_exit: false },
                launches: { aggression: "firm", block: [], override: true },
                background: { policy: "allow", allow: ["*"], defer: [], prevent: [] },
                scenes: { gaming: "reachable" }
            }
        }
    })

    Store {
        id: store
        name: "mood-policy"
        defaults: root.policyDefaults
    }

    // The live policy from the file (reactive). Falls back to the defaults so
    // a first-run seed or a partially-written file still reads as something.
    readonly property var policyData: store.get("moods") ?? root.policyDefaults.moods

    // The active mood's full policy record (snake_case). Falls back to neutral
    // so a bad/stale `mode` in the file (or mid-migration) never leaves a
    // reader with `undefined.accent_role`.
    readonly property var current: (root.policyData[root.mode] ?? root.policyData.neutral)
        ?? root.policyDefaults.moods.neutral

    // Convenience accessors in the shape the rest of the shell already reads.
    // Theme.qml binds accent/surfaceAlpha to these; Notify reads
    // `Focus.notifications.policy`; Bar reads `Focus.mode`.
    readonly property string accentRole: root.current.accent_role ?? "mauve"
    readonly property real surfaceAlpha: root.current.surface_alpha ?? 0.84
    readonly property var notifications: root.current.notifications ?? {}
    readonly property var launches: root.current.launches ?? {}
    readonly property var background: root.current.background ?? {}
    readonly property var scenes: root.current.scenes ?? {}

    // Kinds some active mood refuses, derived from the same policy store the
    // launchers read — the union today is media+game, and it stays the union
    // whatever `launches.block` grows to.
    readonly property var blockedKinds: Object.keys(root.policyData)
        .reduce((acc, id) => acc.concat((root.policyData[id].launches ? root.policyData[id].launches.block : null) || []), [])
        .filter((v, i, a) => a.indexOf(v) === i)

    // Live even past `until`: a stale non-neutral mood that nothing has
    // cleared yet should stop blocking (and read as neutral) on its own,
    // rather than wait for the next explicit `stop()`.
    readonly property bool active: root.mode !== "neutral" &&
        (root.until === null || Date.now() < Date.parse(root.until))

    // Refuse-to-start at dispatch time. Reads the ACTIVE mood's launch policy
    // from the store: `soft` warns and lets through, `firm`/`hard` refuse.
    // A mood never blocks launching into itself — entering `game` is how you
    // start gaming, so it cannot also refuse the game launch that got you
    // there. Neutral blocks nothing (`active` is false at rest).
    // The launch kind a mood id owns. The launch vocabulary ("media", "game")
    // and the mood ids ("work", "study", "gaming") stopped overlapping when the
    // mood set was trimmed, so "a mood never blocks launching into itself"
    // needs this one link: the game kind is the gaming mood's own territory.
    readonly property var kindOwner: ({ game: "gaming" })

    function canLaunch(kind) {
        if (!root.active) return true;
        if (root.mode === kind || root.kindOwner[kind] === root.mode) return true;
        const launch = root.current.launches || {};
        const blocked = Array.isArray(launch.block) && launch.block.indexOf(kind) >= 0;
        return !blocked || launch.aggression === "soft";
    }

    function blockReason(kind) {
        if (root.canLaunch(kind)) return "";
        const until = root.until ? (" until " + root.until) : "";
        return root.current.name + " is on" + until + " — this is blocked while it runs";
    }

    // Scene reachability for the active mood: absent is reachable; an
    // inactive mood restricts nothing. Only explicit "blocked" in the
    // policy takes away access; the active mood never locks itself out.
    function sceneState(scene) {
        if (!root.active) return "reachable";
        return root.current.scenes ? (root.current.scenes[scene] || "reachable") : "reachable";
    }

    // A background task's effective level for the active mood — the
    // single definitional resolver (MoodPanel and ,scene-apply.sh agree
    // by both reading this). Absent = allow; wildcard covers everything
    // not individually listed; a "deny" gate blocks unlisted tasks.
    function backgroundTaskLevel(task) {
        if (!root.active) return "allow";
        const bg = root.current.background || {};
        const allow = bg.allow || [];
        const defer = bg.defer || [];
        const prevent = bg.prevent || [];
        if (prevent.indexOf(task) >= 0) return "prevent";
        if (defer.indexOf(task) >= 0) return "defer";
        if (allow.indexOf("*") >= 0 || allow.indexOf(task) >= 0)
            return bg.policy === "deny" ? "blocked" : "allow";
        return bg.policy === "deny" ? "blocked" : "unset";
    }

    // Enter a mood. `minutes` <= 0 (or omitted) means open-ended (only
    // `stop()`, or another `set()`, ends it).
    function set(mode, minutes) {
        if (!root.policyData[mode]) return;
        const until = (minutes && minutes > 0)
            ? new Date(Date.now() + minutes * 60000).toISOString()
            : null;
        stateStore.set({ mode: mode, until: until });
    }

    // The explicit override: back to the resting state. Also what a lapsed
    // timed mood settles to on its own via `active`.
    function stop() { stateStore.set({ mode: "neutral", until: null }); }

    // Deep-merge a policy patch into one mood and persist to the store file —
    // the one writer the mood UI and any later editor funnel through, so a UI
    // edit and a hand edit of mood-policy.json cannot fight. `patch` replaces
    // the listed keys of the fully-resolved mood record wholesale: the panel
    // passes complete nested objects (it reads `current` first), it never
    // patches fragments of a sub-object.
    function patchMood(mode, patch) {
        if (!root.policyData[mode] || typeof patch !== "object") return;
        const merged = Object.assign({}, root.policyData[mode], patch);
        store.set({ moods: Object.assign({}, root.policyData, { [mode]: merged }) });
    }

    // Whenever the ACTIVE mood changes: the enforced seam (bin/,scene-apply.sh)
    // brings user-unit background work in line with the new policy (start what
    // the new mood allows, stop what it refuses). Fire-and-forget and detached:
    // the script reads focus.json itself and does the systemd work, so a
    // missing/failed script never blocks the shell. Runs at rest (neutral)
    // too, so leaving a mood hands the stopped units back.
    function _applyScene() {
        if (!root._hydrated) return;
        const mode = root.active ? root.mode : "neutral";
        root.runSceneApply(mode);
    }

    // The enforced seam itself lives in the hypr repo's bin/ (bin/,scene-apply.sh)
    // — this is only the trigger, and the process runs async so Focus never
    // waits on it. Absent a script on PATH the run just fails silently.
    Process { id: sceneApply; command: [",scene-apply.sh", "neutral"] }
    function runSceneApply(mode) {
        sceneApply.command = [",scene-apply.sh", mode];
        sceneApply.running = true;
    }

    // The compositor's half of a mode change, driven the moment the pointer
    // moves: the shell writes the pointer, then asks the compositor to
    // converge on it through `hyprctl eval` — `hyprfocus.converge` applies the
    // workspaces/bindings half and hands the services half to the CLI, without
    // rewriting the pointer we just wrote. The watcher (the Lua side) is the
    // cheap fallback that covers writers outside the shell; this trigger is
    // what keeps mode entry synchronous with the mood centre rather than
    // waiting for the desk's next event.
    // Fails open: no hyprctl / wrong eval never blocks the pointer.
    Process { id: converge; command: ["hyprctl", "eval", ""] }
    function runConverge(mode) {
        converge.command = ["hyprctl", "eval", 'require("hypr.hyprfocus.init").converge("' + mode + '")'];
        converge.running = true;
    }

    Connections {
        target: root
        function onModeChanged() {
            root._applyScene();
            root.runConverge(root.active ? root.mode : "neutral");
        }
    }

    // ipc: qs -c quantumfate ipc call focus <fn>
    IpcHandler {
        target: "focus"
        function status(): string {
            return root.mode + (root.until ? (" until " + root.until) : "");
        }
        // Enter a mood: `ipc call focus set deep 90` (90 minutes), or
        // `ipc call focus set deep 0` for open-ended.
        function set(mode: string, minutes: int): void { root.set(mode, minutes); }
        function stop(): void { root.stop(); }
        // "yes" / "no: <reason>" — a launcher script greps the first word.
        function canLaunch(kind: string): string {
            return root.canLaunch(kind) ? "yes" : ("no: " + root.blockReason(kind));
        }
        // "reachable" / "blocked" — a dispatcher (workspace gates, focus-guard)
        // greps the verdict when deciding whether to enter a scene.
        function scene(name: string): string { return root.sceneState(name); }
        // "allow" / "defer" / "prevent" / "unset" / "blocked" — the task-level
        // verdict the DBus/CLI background gates read at dispatch time.
        function bg(task: string): string { return root.backgroundTaskLevel(task); }
        function reload(): void { stateStore.reload(); store.reload(); }
    }
}