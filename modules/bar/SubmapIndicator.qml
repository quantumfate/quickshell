// SubmapIndicator — the active submap's name, inline on the bar.
//
// The bar stays honest about context: in a submap the name shows, at root it
// hides so the bar does not carry dead state. Plain text on the island it
// already sits in — a chip inside a chip read as a second surface.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme

Item {
    id: root

    property string submap: ""
    readonly property bool inSubmap: root.submap !== "" && root.submap !== "reset"

    visible: root.inSubmap
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") root.submap = event.data;
        }
    }

    RowLayout {
        id: row
        anchors.fill: parent
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
