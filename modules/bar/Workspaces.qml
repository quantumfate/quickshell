// Workspaces bar module: a surface pill of per-workspace buttons for this
// monitor. Active = mauve, hover = text, idle = overlay0 (waybar palette).
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

    color: Theme.c.surface0
    radius: Theme.radiusPill
    implicitWidth: row.implicitWidth + 8
    implicitHeight: 22

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: Hyprland.workspaces

            delegate: Rectangle {
                required property var modelData
                readonly property bool onThisMonitor: modelData.monitor === root._monitor
                readonly property bool active: modelData.active
                // Special workspaces have negative ids — never list them.
                readonly property bool special: modelData.id < 0

                visible: onThisMonitor && !special
                implicitWidth: label.implicitWidth + 14; implicitHeight: 20
                radius: 8
                color: "transparent"

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: modelData.name
                    color: active ? Theme.c.mauve : ws.hovered ? Theme.c.text : Theme.c.overlay0
                    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
                }
                HoverHandler { id: ws }
                TapHandler { onTapped: modelData.activate() }
            }
        }
    }
}
