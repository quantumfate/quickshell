// System tray: StatusNotifierItem icons. Left-click activates; right-click opens
// the item's real context menu (via QsMenuAnchor / DBusMenu), falling back to
// secondary activation for items that expose no menu.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import "../../services"   // Theme

RowLayout {
    spacing: 6

    Repeater {
        model: SystemTray.items

        delegate: Item {
            id: entry
            required property var modelData
            Layout.preferredWidth: 14; Layout.preferredHeight: 14

            Image {
                id: icon
                anchors.fill: parent
                source: entry.modelData.icon
                sourceSize.width: 14; sourceSize.height: 14
                fillMode: Image.PreserveAspectFit
            }

            // Native context menu, anchored under the icon.
            QsMenuAnchor {
                id: menu
                menu: entry.modelData.menu
                anchor.item: icon
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (m) => {
                    if (m.button === Qt.RightButton) {
                        if (entry.modelData.hasMenu) menu.open();
                        else entry.modelData.secondaryActivate();
                    } else {
                        entry.modelData.activate();
                    }
                }
            }
        }
    }
}
