// Toasts — renders the Notify queue as themed cards under the bar, top-centered
// on the wide screen. Passive overlay: never takes focus, click-through.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Notify, Theme

PanelWindow {
    id: win
    color: "transparent"
    visible: Notify.items.length > 0

    anchors { top: true; left: true; right: true }
    margins { top: 38 }                       // just below the 30px bar
    implicitHeight: Math.max(1, col.implicitHeight)

    // Overlay layer + no exclusive zone: pops on top, never reserves tiling space.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0

    ColumnLayout {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6

        Repeater {
            model: Notify.items

            delegate: Rectangle {
                required property var modelData
                readonly property color accent: modelData.level === "success" ? Theme.success
                    : modelData.level === "error" ? Theme.error : Theme.accent

                Layout.alignment: Qt.AlignHCenter
                implicitWidth: content.implicitWidth + 24
                implicitHeight: content.implicitHeight + 14
                radius: Theme.radiusPill
                color: Theme.withAlpha(Theme.backgroundAlt, 0.96)
                border { width: 1; color: accent }

                RowLayout {
                    id: content
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle { width: 6; height: 6; radius: 3; color: parent.parent.accent; Layout.alignment: Qt.AlignVCenter }
                    Text {
                        text: modelData.summary + (modelData.body ? "  " + modelData.body : "")
                        color: Theme.text
                        font { family: Theme.fontFamily; pixelSize: 12; weight: Theme.barFontWeight }
                    }
                }
            }
        }
    }
}
