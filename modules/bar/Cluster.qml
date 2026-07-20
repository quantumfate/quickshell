// Cluster — a rounded surface group for a row of bar modules, so related widgets
// read as one segment instead of floating loose on the bar background. Matches
// the Workspaces/Clock pills. Children are laid out in an internal Row.
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme

Rectangle {
    id: root
    // Modules placed inside a Cluster go into the internal row.
    default property alias content: row.data

    color: Theme.surface
    radius: Theme.radiusPill
    border { width: 1; color: Theme.withAlpha(Theme.border, 0.5) }
    implicitWidth: row.implicitWidth + 12
    implicitHeight: 22

    RowLayout {
        id: row
        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
        spacing: 2
    }
}
