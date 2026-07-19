// TipLayer — renders the current hover tooltip for one screen, as its own layer
// surface just below the bar (Controls popups can't escape the 30px bar window).
// Passive overlay: no focus, no exclusive zone, so it never disturbs tiling.
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../services"   // Tip, Theme

PanelWindow {
    id: win
    required property var screen

    readonly property var tip: Tip.byScreen[screen.name]
    visible: tip !== undefined
    color: "transparent"

    anchors { top: true; left: true; right: true }
    margins { top: 32 }
    implicitHeight: 30

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0

    Rectangle {
        visible: win.tip !== undefined
        // Center under the anchor, clamped to stay on-screen.
        x: win.tip ? Math.max(4, Math.min(win.tip.x - width / 2, win.width - width - 4)) : 0
        y: 0
        implicitWidth: label.implicitWidth + 20
        implicitHeight: label.implicitHeight + 10
        radius: Theme.radiusPill
        color: Theme.backgroundAlt
        border { width: 2; color: Theme.surface }

        Text {
            id: label
            anchors.centerIn: parent
            text: win.tip ? win.tip.text : ""
            color: Theme.text
            font { family: Theme.fontFamily; pixelSize: 12 }
        }
    }
}
