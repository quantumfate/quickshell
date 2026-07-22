// Workspaces bar module: a surface pill of per-workspace buttons for this
// monitor, in ascending id order, each shown as a Nerd Font icon.
//   active   → mauve, filled pill
//   occupied → lavender (has windows)
//   idle     → overlay0
//   urgent   → red
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../services"   // Theme

Rectangle {
    id: root

    // The monitor this bar instance lives on; filters which workspaces show.
    required property var screen
    readonly property var _monitor: Hyprland.monitorFor(screen)

    // Per-workspace icon by name (from Hyprland default_name), else by id, else a
    // generic dot. Add a workspace = add a line here.
    readonly property var _iconByName: ({
        "code": "",    //  terminal
        "study": "",   //  book
        "proton": "",  //  envelope
        "media": "",   //  music
        "gaming": ""   //  gamepad
    })
    function _icon(wsName, wsId) {
        return root._iconByName[wsName] ?? (wsId > 0 && wsId < 10 ? String(wsId) : ""); //  dot
    }

    // This monitor's real (non-special) workspaces, sorted by id — the model
    // order Hyprland hands us is creation order, which is why the raw list looked
    // shuffled. `_tick` re-evaluates the list on every compositor event.
    property int _tick: 0
    Connections { target: Hyprland; function onRawEvent(e) { root._tick++; } }
    readonly property var _sorted: {
        root._tick; // dependency
        return (Hyprland.workspaces?.values ?? [])
            .filter(w => w.monitor === root._monitor && w.id > 0)
            .sort((a, b) => a.id - b.id);
    }

    color: "transparent"
    implicitWidth: row.implicitWidth
    implicitHeight: 22

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 10

        Repeater {
            model: root._sorted

            // Icon only — the active workspace is signalled purely by icon colour
            // (mauve), never a background.
            delegate: Text {
                required property var modelData
                readonly property bool active: modelData.active
                readonly property bool occupied: (modelData.toplevels?.values?.length ?? 0) > 0
                readonly property bool urgent: modelData.urgent ?? false

                text: root._icon(modelData.name, modelData.id)
                color: urgent ? Theme.c.red
                     : active ? Theme.c.mauve
                     : ws.hovered ? Theme.c.text
                     : occupied ? Theme.c.lavender
                     : Theme.c.overlay0
                font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }

                HoverHandler { id: ws }
                TapHandler { onTapped: modelData.activate() }
            }
        }
    }
}
