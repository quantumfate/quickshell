// Class emblem: the real DofusDB class artwork, shown at `size`. Renders
// nothing when `cls` is empty or unknown, so it can sit unconditionally on any
// card and simply vanish when no class is set. `color` is an optional flat tint
// (transparent = off) for callers that want a single-colour silhouette instead.
import QtQuick
import Qt5Compat.GraphicalEffects   // ColorOverlay (only when tinting)
import "../../services"             // DofusClasses

Item {
    id: root
    property string cls: ""
    property color color: "transparent"   // set to a colour to flat-tint the art
    property int size: 20
    readonly property bool _tinted: color.a > 0
    visible: cls !== "" && DofusClasses.has(cls)
    implicitWidth: size
    implicitHeight: size

    Image {
        id: src
        anchors.fill: parent
        source: DofusClasses.iconFor(root.cls)
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        fillMode: Image.PreserveAspectFit
        // Hidden only while an overlay recolours it; otherwise this is the icon.
        visible: !root._tinted
    }
    ColorOverlay {
        anchors.fill: src
        source: src
        color: root.color
        visible: root._tinted
    }
}
