// HoverDetail — a fixed-height text slot for hover-preview content, built so
// nothing under the pointer ever moves (LEO-384). The mode panel used to draw
// its transition preview as a `Text` that was only in the layout while
// visible, so the whole card's height jumped as the pointer crossed chips.
// This component reserves `lines` worth of height unconditionally — an empty
// string and a two-line preview occupy the exact same box.
//
// Pair with any hoverEnabled control (PalettePicker.onHoverName, a chip's own
// MouseArea, ...): the caller owns the string, this owns the space for it.
// Shared with the theme panel (LEO-366).
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme

Item {
    id: root

    property string text: ""
    property color textColor: Theme.subtextAlt
    property int lines: 2

    Layout.fillWidth: true
    implicitHeight: label.font.pixelSize * root.lines * 1.4

    Text {
        id: label
        anchors.fill: parent
        text: root.text
        color: root.textColor
        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        verticalAlignment: Text.AlignTop
        maximumLineCount: root.lines
        elide: Text.ElideRight
    }
}
