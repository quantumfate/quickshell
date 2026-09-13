// A floating island of bar modules.
//
// The bar is not a chrome slab across the top of the screen — it is a few
// translucent cards resting on the wallpaper, with real space between them and
// real wallpaper showing through. The compositor frosts whatever is painted
// above `ignore_alpha` (see the quickshell-bar layer rule), which is why the
// island carries the alpha and the bar behind it carries none: the glass is
// blurred, the gaps between islands are not.
//
// Radius is deliberately short of a lozenge. A pill reads as a button; this is
// a surface.
import QtQuick
import QtQuick.Layouts
import "../../services"

Rectangle {
    id: root

    default property alias content: row.data
    property alias spacing: row.spacing

    implicitWidth: row.implicitWidth + Theme.space.lg * 2
    implicitHeight: Theme.barHeight

    radius: Theme.radiusIsland
    color: Theme.withAlpha(Theme.backgroundAlt, 0.72)
    border { width: 1; color: Theme.withAlpha(Theme.border, 0.45) }

    RowLayout {
        id: row
        anchors {
            fill: parent
            leftMargin: Theme.space.lg
            rightMargin: Theme.space.lg
        }
        spacing: Theme.space.lg
    }
}
