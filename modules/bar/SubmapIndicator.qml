// SubmapIndicator — a small pill on the bar that names the active submap.
//
// The bar stays honest about context: when Hyprland is in a submap, the pill
// shows its name. At root the pill hides so the bar does not carry dead state.
// The pill uses the bar's island material tinted toward the accent.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme
import "../common"        // Surface

Surface {
    id: root

    property string submap: ""
    readonly property bool inSubmap: root.submap !== "" && root.submap !== "reset"

    visible: root.inSubmap
    elevation: "island"
    color: Theme.withAlpha(Theme.accent, 0.18)
    border { width: 1; color: Theme.withAlpha(Theme.accent, 0.45) }
    radius: Theme.radiusSmall

    implicitWidth: row.implicitWidth + Theme.space.md * 2
    implicitHeight: Theme.barHeight

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") root.submap = event.data;
        }
    }

    RowLayout {
        id: row
        anchors { fill: parent; leftMargin: Theme.space.md; rightMargin: Theme.space.md }
        spacing: Theme.space.xs

        Text {
            text: "map"
            color: Theme.accent
            font { pixelSize: Theme.fs.xs; bold: true }
        }
        Text {
            text: root.submap
            color: Theme.text
            font.pixelSize: Theme.fs.sm
        }
    }
}
