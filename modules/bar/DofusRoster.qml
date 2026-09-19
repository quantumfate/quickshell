// DofusRoster — Dofus-only bar isle for the dofus workspace (LEO-234).
//
// This is not attached to a window or Hyprland group; it is a bar cluster that
// mirrors the group order from DofusWindows and exposes the swap-detector
// controls from DofusSwap. It appears only while the active workspace on this
// monitor is the dofus workspace and Dofus clients are present.
//
// Layout per request:
//   [ (class icon, Character) chip, learn button ] ... [ recalibrate ] [ run/stop ]
//
// Membership comes from DofusWindows (the live Hyprland group read model), not
// reconstructed anywhere else. Swap state comes from DofusSwap.
//
// LEO-376: the isle used bare Text as its controls — no hover/pressed state,
// no hit target past the glyphs, no focus ring. Every action here now renders
// through DofusRosterButton.qml, the same rounded/alpha-tinted chip idiom as
// modules/common/PalettePicker.qml, so the bar doesn't read as a second
// button language next to the mode panel's. Behaviour is unchanged — same
// DofusWindows.focus/DofusSwap calls as before, just under real controls.
pragma ComponentBehavior: Bound
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, Focus, DofusWindows, DofusState, DofusSwap, Tip
import "../common"        // Surface, ClassIcon
import "../whichkey/WhichKey.js" as WK   // fadeFor — shared motion-energy contract

Surface {
    id: root

    required property var screen
    readonly property var _mon: Hyprland.monitorFor(screen)
    readonly property string _screenName: screen?.name ?? ""
    readonly property int _fade: WK.fadeFor(Focus.motionEnergy, 0, 90)

    // Visible only on the dofus workspace while Dofus clients are present.
    readonly property bool _onDofus: _mon?.activeWorkspace?.name === "dofus"
    readonly property bool _hasDofus: (DofusWindows.windows ?? []).some(
        w => w.workspaceId === _mon?.activeWorkspace?.id)
    visible: root._onDofus && root._hasDofus

    elevation: "island"
    implicitHeight: Theme.barHeight * 1.2
    implicitWidth: row.implicitWidth + Theme.space.xl * 2

    RowLayout {
        id: row
        anchors {
            fill: parent
            leftMargin: Theme.space.xl
            rightMargin: Theme.space.xl
        }
        spacing: Theme.space.lg

        // Roster rows, one per group member in group order. Each member is a
        // soft chip (class icon + name, PalettePicker's rounded/alpha idiom)
        // that focuses the character on click, plus its own "learn" button.
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

                Rectangle {
                    id: chip
                    implicitHeight: Theme.barHeight * 0.68
                    implicitWidth: nameRow.implicitWidth + Theme.space.md * 2
                    radius: Theme.radiusSmall
                    color: chipArea.pressed ? Theme.withAlpha(Theme.accent, 0.28)
                         : chipRow.active ? Theme.withAlpha(Theme.accent, 0.18)
                         : chipArea.containsMouse ? Theme.withAlpha(Theme.surface, 0.8)
                         : Theme.withAlpha(Theme.surface, 0.5)
                    border {
                        width: chip.activeFocus ? 2 : 1
                        color: chip.activeFocus ? Theme.accent
                             : chipRow.active ? Theme.accent
                             : Theme.withAlpha(Theme.border, 0.5)
                    }
                    activeFocusOnTab: true
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on color { ColorAnimation { duration: root._fade } }
                    Behavior on border.color { ColorAnimation { duration: root._fade } }

                    RowLayout {
                        id: nameRow
                        anchors.centerIn: parent
                        spacing: Theme.space.xs

                        ClassIcon {
                            cls: chipRow.cls
                            size: 20
                            Layout.preferredWidth: visible ? size : 0
                            Layout.preferredHeight: size
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            text: chipRow.named ? chipRow.character : (chipRow.index + 1) + "."
                            color: chipRow.active ? Theme.accent
                                 : chipRow.named ? Theme.text : Theme.overlay
                            font { pixelSize: Theme.fs.xs; family: "monospace"; bold: chipRow.active }
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    MouseArea {
                        id: chipArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { chip.forceActiveFocus(); DofusWindows.focus(chipRow.modelData.selector); }
                    }

                    HoverTip {
                        text: chipRow.named ? ("Focus " + chipRow.character) : ""
                        shown: chip.activeFocus || (chipArea.containsMouse && chipRow.named)
                        screenName: root._screenName
                    }

                    Keys.onReturnPressed: DofusWindows.focus(chipRow.modelData.selector)
                    Keys.onEnterPressed: DofusWindows.focus(chipRow.modelData.selector)
                    Keys.onSpacePressed: DofusWindows.focus(chipRow.modelData.selector)
                }

                // Learn button: grab this character's turn-popup hash.
                DofusRosterButton {
                    visible: chipRow.named
                    compact: true
                    text: "learn"
                    tooltip: "Learn " + chipRow.character + "'s turn popup"
                    screenName: root._screenName
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: DofusSwap.learn(chipRow.character)
                }
            }
        }

        // Separator between roster and controls.
        Rectangle {
            visible: controlRow.visible
            Layout.preferredWidth: 1
            Layout.preferredHeight: Theme.barHeight * 0.6
            color: Theme.withAlpha(Theme.c.overlay0, 0.6)
            Layout.alignment: Qt.AlignVCenter
        }

        // Swap-detector controls.
        RowLayout {
            id: controlRow
            spacing: Theme.space.sm
            Layout.alignment: Qt.AlignVCenter

            // Recalibrate the turn-popup region.
            DofusRosterButton {
                text: "recalibrate"
                toggled: DofusSwap.calibrating
                tone: Theme.c.yellow
                tooltip: DofusSwap.calibrating
                    ? "select the turn-popup region..."
                    : "Recalibrate turn-popup region"
                screenName: root._screenName
                Layout.alignment: Qt.AlignVCenter
                onClicked: DofusSwap.calibrate()
            }

            // Start / stop the detector.
            DofusRosterButton {
                text: DofusSwap.detectorRunning ? "stop" : "start"
                toggled: true
                tone: DofusSwap.detectorRunning ? Theme.c.red : Theme.c.green
                tooltip: DofusSwap.detectorRunning
                    ? "Stop swap detector"
                    : "Start swap detector"
                screenName: root._screenName
                Layout.alignment: Qt.AlignVCenter
                onClicked: DofusSwap.toggle()
            }
        }
    }
}
