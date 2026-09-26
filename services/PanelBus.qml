pragma Singleton
// PanelBus — open/close state and monitor routing for the bar's click-to-open
// detail panels (projects dashboard, calendar, mood) and any IPC/keybind
// triggered panel that wants to share the same routing decision.
//
// Routing contract (LEO-328):
//   - Bar interactions set the anchor screen explicitly (the bar instance that
//     was clicked).
//   - IPC/keybind interactions resolve the active monitor and set that as the
//     anchor before opening.
//   - Panels render on `anchorScreen`; an empty/missing anchor falls back to
//     the active monitor so nothing silently opens on an arbitrary screen.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import "."
import "SurfacePlacement.js" as SurfacePlacement
import "SurfaceDefaults.js" as SurfaceDefaults
import "BarGaps.js" as BarGaps

Item {
    id: root

    // Which panel is open ("" = none): "projects" | "calendar" | "mood".
    property string open: ""
    property string anchorScreen: ""
    // The isle that opened the current panel, when it came from a bar click.
    // Panels derive their horizontal anchor from the isle's published dock
    // document so they stay aligned with the isle even when it moves.
    property string anchorIsleId: ""
    property real _fallbackAnchorX: 0

    // Horizontal anchor for panels. When an isle opened the panel and the
    // geometry store carries a dock for it, use the dock's anchor; otherwise
    // fall back to the click coordinate passed to toggle(). Kept as a binding
    // so the panel tracks a live dock move while it is open.
    readonly property real anchorX: {
        if (!root.anchorScreen || !root.anchorIsleId) return root._fallbackAnchorX;
        const docks = geometryStore.data ? geometryStore.data.docks : undefined;
        const screenDocks = docks ? docks[root.anchorScreen] : undefined;
        const dock = screenDocks ? screenDocks[root.anchorIsleId] : undefined;
        return (dock && dock.anchor) ? dock.anchor.x : root._fallbackAnchorX;
    }

    // The seat: the keyboard's monitor, published by hypr's `seat.lua` to the
    // `geometry` store's `seat.monitor` key on every change (one seat,
    // cross-repo). This used to read `Hyprland.focusedMonitor`, which tracks
    // the POINTER on this desk (`mouse_move_focuses_monitor = true`) — a
    // widget opening "where the user is" would follow the mouse, not the
    // keyboard, the moment the two disagreed. `focusedMonitor` is kept only as
    // the pre-publish fallback: before hypr's first `seat` write (shell just
    // started, or an old store with no `seat` key yet) there is nothing else
    // to read.
    readonly property string activeScreen: {
        const seat = geometryStore.data ? geometryStore.data.seat : undefined;
        return (seat && seat.monitor) || Hyprland.focusedMonitor?.name || "";
    }

    // Per-screen active workspace/scene name, fed by the compositor's raw
    // workspace events. Kept in this singleton so gap-aware surfaces (Toasts)
    // and the bar itself share one source of truth instead of duplicating the
    // raw-event listener.
    property var sceneByScreen: ({})

    // The scene each screen is standing in, as the compositor PUBLISHED it
    // (geometry store, written by the same layout pass that places the
    // windows). Prefer this over `sceneByScreen` wherever a widget describes
    // its own screen's contents: the event-fed map goes stale the moment an
    // event is missed — measured, a screen standing on `code-deck` read as
    // `loose`, and every scene-scoped widget filtered itself down to nothing
    // — and it reports the deck's hold while a park is in flight. Falls back
    // to the event map for a screen the desk has not published yet.
    function sceneOn(screenName) {
        // Both sources are read FIRST, before the name is even checked. A QML
        // binding tracks the properties it reads while evaluating, and the
        // early `if (!screenName) return ""` registered none of them: a
        // caller whose screen name resolves a moment after its first
        // evaluation (the bar's own workspace row, after a shell restart)
        // therefore never re-evaluated and stayed on "" for the life of the
        // shell. Same trap OpenProjects.qml's `shown` documents.
        const scenes = geometryStore.data ? geometryStore.data.scenes : undefined;
        const events = root.sceneByScreen;
        if (!screenName) return "";
        const published = scenes ? scenes[screenName] : undefined;
        return published || events[screenName] || "";
    }

    // Seeded once at startup, because the map above is fed by EVENTS and a
    // shell that just started has missed all of them: until the first
    // workspace change, every surface reading it sees an empty map and
    // renders nothing at all — which looks like a broken widget rather than
    // like "no scene". `hyprctl monitors` is the same answer the events
    // carry, just asked for rather than waited for.
    Process {
        id: sceneSeed
        running: true
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let monitors = [];
                try { monitors = JSON.parse(this.text || "") || []; }
                catch (e) { return; }   // a bad read just leaves the events to fill it in
                const next = Object.assign({}, root.sceneByScreen);
                for (const m of monitors) {
                    // Never overwrite: an event that landed while this was in
                    // flight is newer than the snapshot it raced.
                    if (m.name && m.activeWorkspace?.name && !next[m.name])
                        next[m.name] = m.activeWorkspace.name;
                }
                root.sceneByScreen = next;
            }
        }
        stderr: StdioCollector {}
    }

    // The focused Hyprland monitor's output name, for workspace events that do
    // not carry their own screen.
    function _focusedScreen() {
        return (Quickshell.screens.find(s => Hyprland.monitorFor(s)?.focused) ?? {}).name ?? "";
    }

    // Resolve a numeric workspace id from focusedmonv2 to its live name. Match
    // by screen first so duplicate auto ids (e.g. -1 for named workspaces) do
    // not pick the wrong workspace.
    function _workspaceById(id, screenName) {
        if (id === undefined || id === null) return null;
        const values = Hyprland.workspaces?.values ?? [];
        return values.find(w => w.id === id && w.monitor?.name === screenName)
            || values.find(w => w.id === id);
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const data = event.data ?? "";
            const comma = data.indexOf(",");
            let name = null, screen = null;
            if (event.name === "workspace") {
                // payload: WORKSPACENAME
                name = data;
            } else if (event.name === "workspacev2") {
                // payload: WORKSPACEID,WORKSPACENAME
                if (comma === -1) return;
                name = data.slice(comma + 1);
            } else if (event.name === "focusedmon") {
                // payload: MONNAME,WORKSPACENAME
                if (comma === -1) return;
                screen = data.slice(0, comma);
                name = data.slice(comma + 1);
            } else if (event.name === "focusedmonv2") {
                // payload: MONNAME,WORKSPACEID
                if (comma === -1) return;
                screen = data.slice(0, comma);
                const id = parseInt(data.slice(comma + 1), 10);
                if (isNaN(id)) return;
                name = root._workspaceById(id, screen)?.name ?? "";
                if (!name) return; // do not overwrite the map with an unresolved id
            }
            if (!name) return;
            if (!screen) {
                const live = (Hyprland.workspaces?.values ?? []).find(w => w.name === name);
                screen = live?.monitor?.name ?? root._focusedScreen();
            }
            if (screen && name) {
                const next = Object.assign({}, root.sceneByScreen);
                next[screen] = name;
                root.sceneByScreen = next;
            }
        }
    }

    Store { id: geometryStore; name: "geometry" }

    function toggle(name, screen, x, isleId) {
        root.anchorScreen = screen;
        root._fallbackAnchorX = x;
        root.anchorIsleId = isleId || "";
        root.open = (root.open === name) ? "" : name;
    }
    function close(name) { if (root.open === name) root.open = ""; }

    // Open a panel from an IPC/keybind path: resolve the active monitor, set it
    // as the anchor, then open the named panel.
    function openFromIpc(name) {
        root.anchorScreen = root.activeScreen;
        root._fallbackAnchorX = 0;
        root.anchorIsleId = "";
        root.open = name;
    }

    // The Quickshell screen object for a given name. Falls back to the active
    // monitor, then to the first available screen, so a panel never opens on a
    // null/invalid output and becomes unreachable.
    function screenObject(name) {
        const target = name || root.activeScreen;
        return Quickshell.screens.find(s => s.name === target)
            ?? Quickshell.screens[0]
            ?? null;
    }

    // ---- surface placement ---------------------------------------------------
    // Where a popup/panel is placed inside hypr's published `areas` (hypr repo
    // docs/scenes.md "Areas", this repo's services/PanelBus.md "Surfaces").
    // The pure math lives in SurfacePlacement.js/SurfaceDefaults.js so it is
    // node-testable; this is the seam that feeds it live state.

    // The active scene's override for `surfaceId` (`Hyprfocus`'s declaration,
    // `base.scenes[name].surfaces[id]`), or its own default when the scene
    // says nothing. hypr never reads `surfaces` — this is quickshell's only
    // consumer of the field.
    function surfaceRequest(screenName, surfaceId) {
        const areasForScreen = geometryStore.data ? (geometryStore.data.areas || {})[screenName] : undefined;
        const scene = areasForScreen ? areasForScreen.scene : undefined;
        const scenes = (Hyprfocus.data && Hyprfocus.data.base) ? Hyprfocus.data.base.scenes : undefined;
        const declared = scene && scenes ? scenes[scene] : undefined;
        const override = declared && declared.surfaces ? declared.surfaces[surfaceId] : undefined;
        return override || SurfaceDefaults.defaultFor(surfaceId);
    }

    // The box a surface should render in on `screenName`, given its own
    // content size. Resolves the request's `of` against hypr's published
    // areas; when the screen has not published yet (shell start, a workspace
    // between scenes), falls back to the monitor less the bar's reserved
    // strip and its resting inset — the same rule a resting bar isle uses, so
    // a surface can never overlap a bar either way. Any cap this applies logs
    // once via console.warn, naming the surface and the overflow.
    function surfaceBox(screenName, surfaceId, contentSize) {
        const request = root.surfaceRequest(screenName, surfaceId);
        const areasForScreen = geometryStore.data ? (geometryStore.data.areas || {})[screenName] : undefined;
        let area = SurfacePlacement.resolveArea(areasForScreen, request.of);
        if (!area) {
            const screenObj = root.screenObject(screenName);
            const screenSize = { width: screenObj ? screenObj.width : 0, height: screenObj ? screenObj.height : 0 };
            const inset = BarGaps.insetFor(geometryStore.data, screenName, Theme.barInset * 2);
            area = SurfacePlacement.restingArea(screenSize, Theme.barReserved, inset);
        }
        return SurfacePlacement.place(area, request, contentSize, (msg) => console.warn("SurfacePlacement:", msg), surfaceId);
    }

    // ---- active monitor resolution -----------------------------------------
    // Provided by `Hyprland.focusedMonitor` above; nothing to poll.

    // projects-health.json, read directly (not via Store — produced by an
    // external repo-scan process, not owned/written by the shell). Missing or
    // unparsable file -> empty repos map, no error surfaced to the user.
    property var projectRepos: ({})
    property bool projectHealthLoaded: false

    FileView {
        id: healthFile
        path: Config.stateDir + "/projects-health.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const doc = JSON.parse(text() || "{}");
                root.projectRepos = doc.projects ?? {};
            } catch (e) {
                root.projectRepos = {};
            }
            root.projectHealthLoaded = true;
        }
        onLoadFailed: {
            root.projectRepos = {};
            root.projectHealthLoaded = true;   // "loaded" = "we tried"; absence is not an error
        }
    }

    // calendar.json, local-only for now — { entries: [{ date, time, title }] }.
    // Structured as its own file (rather than folded into Store) so a later
    // CalDAV source can feed the same `calendarEntries` shape without this
    // file needing to change.
    property var calendarEntries: []
    property bool calendarLoaded: false

    FileView {
        id: calendarFile
        path: Config.stateDir + "/calendar.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const doc = JSON.parse(text() || "{}");
                root.calendarEntries = doc.entries ?? [];
            } catch (e) {
                root.calendarEntries = [];
            }
            root.calendarLoaded = true;
        }
        onLoadFailed: {
            root.calendarEntries = [];
            root.calendarLoaded = true;
        }
    }
}
