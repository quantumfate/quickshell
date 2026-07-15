// Dofus team HUD: shows current ordered team, lets you reorder / edit live.
// Visibility driven by IPC (submap) and Hyprland submap events.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "root:/services"   // DofusState, Config singletons

Scope {
    id: scope

    property bool shown: false

    // Visibility is driven explicitly by the Hyprland Dofus submap, which pushes
    // show/hide/toggle here as it is entered/left (see hypr .../dofus/ipc.lua):
    //   qs -c quantumfate ipc call dofusPanel show|hide|toggle
    IpcHandler {
        target: "dofusPanel"
        function toggle(): void { scope.shown = !scope.shown; }
        function show(): void { scope.shown = true; }
        function hide(): void { scope.shown = false; }
    }

    PanelWindow {
        id: panel
        visible: scope.shown
        color: "transparent"

        anchors { top: true; right: true }
        margins { top: 12; right: 12 }
        implicitWidth: 260
        implicitHeight: col.implicitHeight + 24

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None   // don't steal game focus
        WlrLayershell.namespace: "quickshell-dofus"          // targeted by hypr layerrules

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.withAlpha(Theme.background, 0.87)
            border { width: 1; color: Theme.border }

            ColumnLayout {
                id: col
                anchors { fill: parent; margins: Theme.pad }
                spacing: 6

                Text {
                    text: DofusState.selected.toUpperCase()
                    color: Theme.accent
                    font { pixelSize: 12; bold: true; letterSpacing: 1 }
                }

                Repeater {
                    model: DofusState.team
                    delegate: CharacterRow {
                        Layout.fillWidth: true
                        index: model.index
                        name: modelData
                    }
                }
            }
        }
    }
}
