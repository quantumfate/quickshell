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
import Quickshell.Io
import QtQuick
import "."

Item {
    id: root

    // Which panel is open ("" = none): "projects" | "calendar" | "mood".
    property string open: ""
    property string anchorScreen: ""
    property real anchorX: 0

    // The currently focused Hyprland monitor name, polled so IPC/keybind
    // invocations can anchor panels to the monitor the user is looking at.
    property string activeScreen: ""

    function toggle(name, screen, x) {
        root.anchorScreen = screen;
        root.anchorX = x;
        root.open = (root.open === name) ? "" : name;
    }
    function close(name) { if (root.open === name) root.open = ""; }

    // Open a panel from an IPC/keybind path: resolve the active monitor, set it
    // as the anchor, then open the named panel.
    function openFromIpc(name) {
        root.anchorScreen = root.activeScreen;
        root.anchorX = 0;
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

    // ---- active monitor resolution -----------------------------------------
    Process {
        id: monitorProbe
        command: ["bash", "-lc", "hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'"]
        stdout: StdioCollector { onStreamFinished: root.activeScreen = (this.text || "").trim(); }
    }
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!monitorProbe.running) monitorProbe.running = true
    }

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
