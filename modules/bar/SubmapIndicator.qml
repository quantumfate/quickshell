// SubmapIndicator — the active submap's name, inline on the bar.
//
// The bar stays honest about context: in a submap the name shows, at root it
// hides so the bar does not carry dead state. Plain text on the island it
// already sits in — a chip inside a chip read as a second surface.
//
// It sits in the left isle BEHIND a rule, the same hairline the project strip
// puts between a project and its tabs: "where you are" and "what the keyboard
// is doing" are two questions, and without a divider the submap name read as
// part of the scene's label.
//
// Its height is its content's, never `Theme.barHeight`: the isle is sized by
// its tallest child, so claiming the full bar height made the whole island
// grow the moment a submap opened and shrink again when it closed (live,
// 2026-09-25). The word "map" in front of the name is gone with it — a
// keyboard glyph says the same thing in one character's width.
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
    implicitHeight: row.implicitHeight

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") root.submap = event.data;
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.space.xs

        // The rule, at the height of the text beside it so it reads as a
        // divider rather than another glyph.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 1
            Layout.preferredHeight: Theme.fs.sm
            color: Theme.overlay
            opacity: 0.5
        }

        Text {
            // Nerd Font keyboard: the submap IS the keyboard's current mode.
            text: "\udb80\udf0c"
            color: Theme.accent
            font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
            Layout.alignment: Qt.AlignVCenter
        }
        Text {
            text: root.submap
            color: Theme.text
            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
