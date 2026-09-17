pragma Singleton
// Focus mode: a Store plus the enforcement seam, not the UI.
//
// Two stores live here. `focus.json` is the ACTIVE state — `{ mode, until }` —
// the pointer to the mood the desk is in right now. `mood-policy.json` is the
// DEFINITIONAL store: what each of the six moods *means* (surface alpha,
// notifications, launches, background work, scene reachability). The
// policy store is the source of truth this singleton reads and writes through
// `patchMood`; the shipped default (assets/mood-policy.default.json) is pinned
// identical to the `policyDefaults` literal below by the lockstep test, and the
// panel/editor writes to the same file the Hyprland event manager and the
// launcher scripts read. A mood is therefore one edit away in a JSON file, and
// every runtime reads the same policy.
//
// The accent is NOT part of that policy (LEO-334 item 12, LEO-339): a focus
// mode owns its theme as one of its four controlled things, so the accent
// role lives on the hyprfocus declaration (`modes.*.presentation.accent_role`,
// read through `Hyprfocus`) — the one store both the compositor and the shell
// read. `accentRole` below mirrors that rather than keeping a second copy.
//
// `mode` names one of the declared moods (see `policyDefaults`); `work` is the
// default/resting state every desk starts in and what a lapsed timed mode
// falls back to. `neutral` stays a hidden recovery mode, reached
// only by an explicit manual write, never a fallback. Switching moods is a single `set()` — exactly like
// Theme's palette switch — and everything that reads `Focus.mode` /
// `Focus.current` reacts on its own: Theme.qml binds its `accent` and
// `surfaceAlpha` to `Focus.accentRole`/`Focus.surfaceAlpha`, which are plain
// bindings over the stores, so an edit to the hyprfocus declaration or
// mood-policy.json repaints the shell and re-gates Notify with no reload.
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
import "."   // Theme, Hyprfocus
import "ModeAnnounce.js" as ModeAnnounce
import "ModePrecedence.js" as ModePrecedence

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
        defaults: ({ mode: "work", until: null, previous: null })
    }

    // The raw pointer as written, and `previous` — the mode a timed write
    // carried forward, read back for `mode`'s fallback below.
    readonly property string rawMode: stateStore.get("mode") ?? "work"
    readonly property var until: stateStore.get("until") ?? null
    readonly property var previous: stateStore.get("previous") ?? null

    // The mode as it reads RIGHT NOW: `rawMode` while `until` is unset or
    // still ahead, else `previous` (or `work`, the default/resting mode, if
    // there is none) — never `neutral`, the hidden recovery mode, unless a
    // manual write put it there directly. Every consumer below reads this,
    // not `rawMode`, so a lapsed timed mode falls back on its own.
    readonly property string mode: ModePrecedence.effectiveMode(
        { mode: root.rawMode, until: root.until, previous: root.previous })

    // The definitional per-mood policy, in the store's snake_case shape. This
    // literal IS assets/mood-policy.default.json (the lockstep test pins them
    // identical) and it seeds the state file on first run — so a fresh machine
    // and a hand-migrated one agree on what "deep work" means. `surface_alpha`
    // is the one dial each mood turns on the shared card material (see
    // Theme.qml's `surfaceAlpha` map) — paper, not glass. The accent is NOT
    // here (LEO-339): it lives on the hyprfocus declaration and is read
    // through `Hyprfocus` below. Wallpaper is deliberately absent too:
    // `,theme.sh mood-wallpaper` resolves mood -> wallpaper on its own so this
    // table does not duplicate it.
    readonly property var policyDefaults: ({
        moods: {
            neutral: {
                name: "Neutral", surface_alpha: 0.84,
                density: "comfortable", motion_energy: "base", bar_autohide: false,
                notifications: { policy: "all", position: "top-right", timeout: 6000, queue: false, digest_on_exit: false },
                launches: { aggression: "soft", block: [], override: false },
                background: { defer: [], prevent: [] },
                scenes: {}
            },
            work: {
                name: "Work", surface_alpha: 0.94,
                density: "compact", motion_energy: "instant", bar_autohide: true,
                notifications: { policy: "critical-only", position: "top-right", timeout: 0, queue: true, digest_on_exit: true },
                launches: { aggression: "firm", block: ["media", "game"], override: true },
                background: { defer: [], prevent: [] },
                scenes: { gaming: "blocked", media: "blocked" }
            },
            study: {
                name: "Study", surface_alpha: 0.94,
                density: "compact", motion_energy: "instant", bar_autohide: true,
                notifications: { policy: "critical-only", position: "top-right", timeout: 0, queue: true, digest_on_exit: true },
                launches: { aggression: "firm", block: ["media", "game"], override: true },
                background: { defer: [], prevent: [] },
                scenes: { gaming: "blocked", media: "blocked" }
            },
            gaming: {
                name: "Gaming", surface_alpha: 0.96,
                density: "compact", motion_energy: "instant", bar_autohide: false,
                notifications: { policy: "none", position: "top-right", timeout: 0, queue: true, digest_on_exit: false },
                launches: { aggression: "firm", block: [], override: true },
                background: { defer: [], prevent: [] },
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
    // reader with `undefined.surface_alpha`.
    readonly property var current: (root.policyData[root.mode] ?? root.policyData.neutral)
        ?? root.policyDefaults.moods.neutral

    // Convenience accessors in the shape the rest of the shell already reads.
    // Theme.qml binds accent/surfaceAlpha to these; Notify reads
    // `Focus.notifications.policy`; Bar reads `Focus.mode`.
    //
    // The accent role is the one accessor that does NOT read `current`: the
    // owning store is the hyprfocus declaration (LEO-334 item 12, LEO-339),
    // read through the same `Hyprfocus` singleton the compositor's
    // declaration reader mirrors, not a second copy kept here. `Hyprfocus`
    // tracks the same `focus` pointer this singleton does, so both agree on
    // which mode's accent is active.
    readonly property string accentRole: Hyprfocus.current.presentation?.accent_role ?? "mauve"
    readonly property real surfaceAlpha: root.current.surface_alpha ?? 0.84
    // `"base" | "instant"` — surfaces that animate read this rather than
    // hardcode durations, so a mode's motion contract is one place (which-key
    // uses it to size its entrance/exit fades, LEO-300).
    readonly property string motionEnergy: root.current.motion_energy ?? "base"
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

    // `mode` already resolves a lapsed timed mode to its fallback, so this is
    // just "is the effective mode the hidden recovery one" — neutral is the
    // only mode that blocks nothing.
    readonly property bool active: root.mode !== "neutral"

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

    // A background task's effective level for the active mood — the single
    // definitional resolver (MoodPanel and ,scene-apply.sh agree by both
    // reading this). The background section carries defer/prevent lists only
    // (LEO-252 retired the wildcard policy shape): anything not listed runs.
    function backgroundTaskLevel(task) {
        if (!root.active) return "allow";
        const bg = root.current.background || {};
        const defer = bg.defer || [];
        const prevent = bg.prevent || [];
        if (prevent.indexOf(task) >= 0) return "prevent";
        if (defer.indexOf(task) >= 0) return "defer";
        return "unset";
    }

    // Enter a mood. `minutes` <= 0 (or omitted) means open-ended (only
    // `stop()`, or another `set()`, ends it). Every writer records provenance
    // (LEO-276): "who set this" is a question the desk must answer — the
    // shell's own writes carry `"manual"`, and an automated proposal goes
    // through ModePrecedence.decide before it may land.
    function set(mode, minutes) {
        if (!root.policyData[mode]) return;
        const now = new Date();
        const until = (minutes && minutes > 0)
            ? new Date(now.getTime() + minutes * 60000).toISOString()
            : null;
        // Open-ended entry clears `previous`; a timed entry records what to
        // fall back to once it lapses (carried forward, not nested — see
        // ModePrecedence.nextPrevious).
        const previous = until === null ? null
            : ModePrecedence.nextPrevious({ mode: root.rawMode, until: root.until, previous: root.previous }, now);
        stateStore.set({ mode: mode, until: until, previous: previous, source: "manual", set_at: now.toISOString() });
    }

    // The explicit override: back to the resting state (`work` —
    // `neutral` stays a hidden recovery mode, never the default). Also what a
    // lapsed timed mood settles to on its own via `mode`'s own fallback.
    // Provenance too — a stop is a deliberate write like any other.
    function stop() {
        stateStore.set({
            mode: "work", until: null, previous: null, source: "manual", set_at: new Date().toISOString()
        });
    }

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

    // The announce phase of the reconcile contract (LEO-242): before the
    // enforced half fires, a transition that TAKES something away says what
    // it will take — naming the resources, not just the mode, so "entering
    // gaming" also reads as "stopping linear-sync". The dwell is then the
    // grace window: long enough to interrupt, not so long it reads as a
    // dialog to dismiss reflexively. A transition that takes nothing enforces
    // immediately.
    //
    // The fire time re-reads the pointer rather than trusting what was set
    // when the dwell started — two mode boundaries inside one dwell land on
    // the second one's plan.
    readonly property int graceMs: 800
    function _beginTransition() {
        const name = root.active ? root.mode : "neutral";
        const spec = (Hyprfocus.refresh(), Hyprfocus.current);
        const a = ModeAnnounce.announce(spec, Hyprfocus.label(name));
        if (a) Notify.send(a.title, a.body, "info", true);   // transient: no history entry
        if (!a) { root._enforce(); return; }                 // nothing taken: no grace owed
        grace.restart();
    }
    function _enforce() {
        root._applyScene();
        root.runConverge(root.active ? root.mode : "neutral");
        // The palette a mode leases (LEO-288): entry and exit both fan
        // every external surface out through `,theme.sh apply` — the
        // effective palette moved. The shell-side roles recolour on their
        // own binding; this is the external half.
        Theme.noteLease();
    }
    Timer { id: grace; interval: root.graceMs; onTriggered: root._enforce() }

    Connections {
        target: root
        function onModeChanged() { root._beginTransition(); }
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