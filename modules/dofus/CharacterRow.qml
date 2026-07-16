// One team member: order number, name, up/down reorder, remove.
// Editing here mutates DofusState, which persists to team.json.
import QtQuick
import QtQuick.Layouts
import "../../services"   // DofusState

RowLayout {
    id: row
    // Repeater delegate: the model's `index` and `modelData` roles bind to
    // these required properties (avoids implicit context-property injection).
    required property int index
    required property string modelData
    readonly property string name: modelData
    spacing: 8

    Text {
        text: (row.index + 1) + "."
        color: Theme.subtext
        font.pixelSize: 13
        Layout.preferredWidth: 18
    }

    Text {
        text: row.name
        color: Theme.text
        font.pixelSize: 14
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    // Reorder — order is the whole point, so make it one click.
    RowButton { label: "▲"; onClicked: DofusState.reorder(row.index, row.index - 1) }
    RowButton { label: "▼"; onClicked: DofusState.reorder(row.index, row.index + 1) }
    RowButton { label: "✕"; onClicked: DofusState.remove(row.index) }

    component RowButton: Rectangle {
        property string label
        signal clicked
        width: 20; height: 20; radius: Theme.radiusSmall
        color: ma.containsMouse ? Theme.surface : "transparent"
        Text { anchors.centerIn: parent; text: parent.label; color: Theme.subtext; font.pixelSize: 11 }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: parent.clicked() }
    }
}
