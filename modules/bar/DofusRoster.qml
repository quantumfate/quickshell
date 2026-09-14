// DofusRoster — bar cluster for the team's live windows (LEO-234).
//
// The compositor groupbar is the attached bar on the tile (window titles over
// the groupbar, per the conf theme); this is the BAR's mirror of the same
// truth: one chip per group member, in group order, the active tab accented,
// click to focus. It mounts on this monitor's island only while the group's
// workspace is the active one on this monitor — the same rules the native bar
// follows, and gone without the group.
//
// Membership comes from DofusWindows (the `hyprctl clients -j` snapshot read
// model), never reconstructed anywhere else.
pragma ComponentBehavior: Bound
import Quickshell.Hyprland
import QtQuick
import "../../services"   // Theme, DofusWindows, DofusState

Row {
    id: root

    // The screen (and so the monitor) this bar island belongs to.
    required property var screen
    readonly property var _mon: Hyprland.monitorFor(screen)

    // Up only while the group's workspace is this monitor's active one.
    readonly property bool _onStage: (_mon?.activeWorkspace?.id ?? -1) >= 0
        && (DofusWindows.windows ?? []).some(w => w.workspaceId === _mon.activeWorkspace?.id)

    spacing: Theme.space.sm

    Repeater {
        model: root._onStage ? (DofusWindows.windows ?? []) : []

        Text {
            id: chip
            required property var modelData
            required property int index
            readonly property bool active: modelData.focused ?? false
            readonly property bool named: !!modelData.name

            // The character name where there is one, the roster position
            // otherwise — a group of anywhere-named windows is still readable.
            text: chip.named ? chip.modelData.name : (chip.index + 1) + "."
            color: chip.active ? Theme.accent
                 : chip.named ? Theme.text : Theme.overlay
            font { pixelSize: Theme.fs.xs; family: "monospace"; bold: chip.active }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: DofusWindows.focus(chip.modelData.selector)
            }
        }
    }
}
