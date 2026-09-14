pragma Singleton
// PanelBus — open/close state for the bar's click-to-open detail panels
// (projects dashboard, calendar), plus the one shared read of
// projects-health.json both the pill and the dashboard need. Mirrors
// services/SysMon.qml's pattern (bar cluster reports state, a separate
// top-level panel renders wherever the bus points) but lives in modules/
// since these panels are bar-only, not a cross-shell service.
import Quickshell
import Quickshell.Io
import QtQuick
import "../../services"   // Config

Item {
    id: root

    // Which panel is open ("" = none): "projects" | "calendar" | "mood".
    property string open: ""
    property string anchorScreen: ""
    property real anchorX: 0
    // The Dofus editors (LEO-244): the gaming group widget opens these the same
    // in-process way the bar's panels open — no new IPC surface on top of the
    // one `teamSelector`/`classAssigner` already carry for binds.
    property bool teamSelectorOpen: false
    property bool classAssignerOpen: false

    function toggle(name, screen, x) {
        root.anchorScreen = screen;
        root.anchorX = x;
        root.open = (root.open === name) ? "" : name;
    }
    function close(name) { if (root.open === name) root.open = ""; }

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
