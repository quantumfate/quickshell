// DofusRosterButton — the one control chip DofusRoster.qml builds every
// clickable row from (LEO-376: the roster isle read as text, not controls).
// Same visual idiom as modules/common/PalettePicker.qml's swatch chips —
// rounded rect, alpha-tinted ground, hairline border — so the bar doesn't
// invent a second button language next to the mode panel's. A local file
// rather than modules/common/ because the roster is its only caller today;
// promote it if a second isle needs the same chip.
//
// States a text label never had: hover (background lifts), pressed (dips
// further so a click reads as physical), and a visible keyboard-focus ring
// (Tab reaches it, Return/Space activates it) — required for anything called
// a button. `toggled` recolors border+text with `tone` for on/off controls
// (start/stop, the focused roster member) without a second component.
//
// `iconCls` puts a class emblem inside the button, so a roster member is one
// control (emblem + name) rather than a chip with a button next to it, and
// `marked` prints a small state dot in the corner — the roster uses it for
// "this character's turn hash is learned", which the isle could otherwise
// only say in a tooltip nobody opens mid-fight.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, Focus
import "../common"        // ClassIcon
import "../whichkey/WhichKey.js" as WK   // fadeFor — shared motion-energy contract

Rectangle {
    id: root

    property string text: ""
    property color tone: Theme.accent
    property bool toggled: false
    property bool compact: false
    property string tooltip: ""
    property string screenName: ""
    // Class emblem drawn before the label; "" (or an unknown class) draws
    // nothing and takes no width, so an unassigned character still lines up.
    property string iconCls: ""
    // Small corner dot: an extra state the label itself is not free to carry.
    property bool marked: false
    property color markTone: Theme.c.green
    signal clicked()

    readonly property int _fade: WK.fadeFor(Focus.motionEnergy, 0, 90)

    activeFocusOnTab: true
    implicitHeight: Theme.barHeight * 0.68
    implicitWidth: content.implicitWidth + Theme.space.md * 2 + (root.compact ? 0 : Theme.space.xs)
    radius: Theme.radiusSmall

    color: area.pressed ? Theme.withAlpha(root.toggled ? root.tone : Theme.accent, 0.28)
         : area.containsMouse ? Theme.withAlpha(root.toggled ? root.tone : Theme.accent, 0.16)
         : root.toggled ? Theme.withAlpha(root.tone, 0.12)
         : Theme.withAlpha(Theme.surface, 0.5)
    border {
        width: root.activeFocus ? 2 : 1
        color: root.activeFocus ? Theme.accent
             : root.toggled ? Theme.withAlpha(root.tone, 0.8)
             : Theme.withAlpha(Theme.border, 0.5)
    }

    Behavior on color { ColorAnimation { duration: root._fade } }
    Behavior on border.color { ColorAnimation { duration: root._fade } }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: Theme.space.xs

        ClassIcon {
            cls: root.iconCls
            size: Theme.fs.xl
            Layout.preferredWidth: visible ? size : 0
            Layout.preferredHeight: size
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            id: label
            text: root.text
            color: root.toggled ? root.tone : (area.containsMouse ? Theme.text : Theme.subtext)
            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; bold: root.toggled }
            Layout.alignment: Qt.AlignVCenter

            Behavior on color { ColorAnimation { duration: root._fade } }
        }
    }

    // State dot, top-right. Sized off the type scale so it tracks the shell's
    // own scale rather than a pixel count.
    Rectangle {
        visible: root.marked
        width: Theme.space.sm
        height: width
        radius: width / 2
        color: root.markTone
        anchors {
            top: parent.top
            right: parent.right
            topMargin: Theme.space.xs
            rightMargin: Theme.space.xs
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.forceActiveFocus(); root.clicked(); }
    }

    HoverTip {
        text: root.tooltip
        shown: root.tooltip.length > 0 && (area.containsMouse || root.activeFocus)
        screenName: root.screenName
    }

    Keys.onReturnPressed: root.clicked()
    Keys.onEnterPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()
}
