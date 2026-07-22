// Separator — a thin vertical hairline between bar groups, so clusters read as
// distinct segments. Sits inside a RowLayout; vertically centered, inset a
// little from the bar's full height.
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme

Rectangle {
    Layout.alignment: Qt.AlignVCenter
    Layout.preferredWidth: 1
    Layout.preferredHeight: 14
    color: Theme.withAlpha(Theme.border, 0.8)
}
