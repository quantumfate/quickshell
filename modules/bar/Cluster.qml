// Cluster — a transparent group for a row of related bar modules. Just an
// internal Row with comfortable spacing; grouping now reads from the spacing
// and the Separators between clusters, not a background.
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme

Item {
    id: root
    // Modules placed inside a Cluster go into the internal row.
    default property alias content: row.data

    implicitWidth: row.implicitWidth
    implicitHeight: 22

    RowLayout {
        id: row
        anchors { verticalCenter: parent.verticalCenter; left: parent.left }
        spacing: 8
    }
}
