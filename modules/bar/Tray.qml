// System tray: StatusNotifierItem icons. Left-click activates, right-click hits
// the item's secondary action (waybar tray).
//
// Full context menus (QsMenuAnchor) are a follow-up; primary/secondary
// activation covers the common cases (toggle, open).
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import "../../services"   // Theme

RowLayout {
    spacing: 6

    Repeater {
        model: SystemTray.items

        delegate: Image {
            required property var modelData
            source: modelData.icon
            Layout.preferredWidth: 14; Layout.preferredHeight: 14
            sourceSize.width: 14; sourceSize.height: 14
            fillMode: Image.PreserveAspectFit

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (m) => m.button === Qt.RightButton
                    ? modelData.secondaryActivate()
                    : modelData.activate()
            }
        }
    }
}
