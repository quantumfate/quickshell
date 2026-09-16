// DofusRoster — Dofus-only bar isle for the gaming workspace (LEO-234).
//
// This is not attached to a window or Hyprland group; it is a bar cluster that
// mirrors the group order from DofusWindows and exposes the swap-detector
// controls from DofusSwap. It appears only while the active workspace on this
// monitor is the gaming workspace and Dofus clients are present.
//
// Layout per request:
//   [ (class icon, Character, learn-hash button) ... ] [ recalibrate ] [ run/stop ]
//
// Membership comes from DofusWindows (the live Hyprland group read model), not
// reconstructed anywhere else. Swap state comes from DofusSwap.
pragma ComponentBehavior: Bound
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, DofusWindows, DofusState, DofusSwap, Tip
import "../common"        // Surface, ClassIcon

Surface {
    id: root

    required property var screen
    readonly property var _mon: Hyprland.monitorFor(screen)
    readonly property string _screenName: screen?.name ?? ""

    // Visible only on the gaming workspace while Dofus clients are present.
    readonly property bool _onGaming: _mon?.activeWorkspace?.name === "gaming"
    readonly property bool _hasDofus: (DofusWindows.windows ?? []).some(
        w => w.workspaceId === _mon?.activeWorkspace?.id)
    visible: root._onGaming && root._hasDofus

    elevation: "island"
    implicitHeight: Theme.barHeight
    implicitWidth: row.implicitWidth + Theme.space.lg * 2

    RowLayout {
        id: row
        anchors {
            fill: parent
            leftMargin: Theme.space.lg
            rightMargin: Theme.space.lg
        }
        spacing: Theme.space.md

        // Roster rows, one per group member in group order.
        Repeater {
            model: DofusWindows.windows ?? []

            RowLayout {
                id: chipRow
                required property var modelData
                required property int index
                readonly property bool active: modelData.focused ?? false
                readonly property bool named: !!modelData.name
                readonly property string character: chipRow.named ? chipRow.modelData.name : ""
                readonly property string cls: chipRow.named ? DofusState.classOf(chipRow.character) : ""

                spacing: Theme.space.xs
                Layout.alignment: Qt.AlignVCenter

                // Class emblem for this character (empty when unassigned).
                ClassIcon {
                    cls: chipRow.cls
                    size: 20
                    Layout.preferredWidth: visible ? size : 0
                    Layout.preferredHeight: size
                    Layout.alignment: Qt.AlignVCenter
                }

                // Character name (or roster position when unnamed).
                Text {
                    id: chip
                    text: chipRow.named ? chipRow.character : (chipRow.index + 1) + "."
                    color: chipRow.active ? Theme.accent
                         : chipRow.named ? Theme.text : Theme.overlay
                    font { pixelSize: Theme.fs.xs; family: "monospace"; bold: chipRow.active }
                    Layout.alignment: Qt.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DofusWindows.focus(chipRow.modelData.selector)
                    }
                }

                // Learn button: grab this character's turn-popup hash.
                Text {
                    id: learnBtn
                    visible: chipRow.named
                    text: "learn"
                    color: learnArea.containsMouse ? Theme.accent : Theme.subtextAlt
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                    Layout.alignment: Qt.AlignVCenter

                    HoverHandler { id: learnHover }
                    HoverTip {
                        text: "Learn " + chipRow.character + "'s turn popup"
                        shown: learnHover.hovered
                        screenName: root._screenName
                    }

                    MouseArea {
                        id: learnArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DofusSwap.learn(chipRow.character)
                    }
                }
            }
        }

        // Separator between roster and controls.
        Rectangle {
            visible: controlRow.visible
            Layout.preferredWidth: 1
            Layout.preferredHeight: Theme.barHeight * 0.5
            color: Theme.c.overlay0
            Layout.alignment: Qt.AlignVCenter
        }

        // Swap-detector controls.
        RowLayout {
            id: controlRow
            spacing: Theme.space.sm
            Layout.alignment: Qt.AlignVCenter

            // Recalibrate the turn-popup region.
            Text {
                id: calibrateLabel
                text: "recalibrate"
                color: DofusSwap.calibrating ? Theme.c.yellow : Theme.text
                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: calibrateHover }
                HoverTip {
                    text: DofusSwap.calibrating
                        ? "select the turn-popup region..."
                        : "Recalibrate turn-popup region"
                    shown: calibrateHover.hovered
                    screenName: root._screenName
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: DofusSwap.calibrate()
                }
            }

            // Start / stop the detector.
            Text {
                id: toggleLabel
                text: DofusSwap.detectorRunning ? "stop" : "start"
                color: DofusSwap.detectorRunning ? Theme.c.red : Theme.c.green
                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: toggleHover }
                HoverTip {
                    text: DofusSwap.detectorRunning
                        ? "Stop swap detector"
                        : "Start swap detector"
                    shown: toggleHover.hovered
                    screenName: root._screenName
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: DofusSwap.toggle()
                }
            }
        }
    }
}
