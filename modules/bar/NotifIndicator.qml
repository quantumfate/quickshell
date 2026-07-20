// NotifIndicator — the bar's notification bell. Left-click opens the history
// panel (NotificationCenter), right-click toggles do-not-disturb. The glyph
// reflects DND; a count rides in the label when history is non-empty.
import QtQuick
import "../../services"   // Notify, Theme

Text {
    id: root
    property string screenName: ""

    readonly property int count: Notify.history.length
    color: Notify.dnd ? Theme.overlay : hover.hovered ? Theme.text : Theme.c.overlay1
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: 10; rightPadding: 10
    text: (Notify.dnd ? "󰂛" : count > 0 ? "󱅫" : "󰂚")
        + (count > 0 ? " " + (count > 99 ? "99+" : count) : "") + " "

    // Left-click opens/closes the history panel, right-click toggles DND — both
    // drive Notify directly (its state is shared with the panel + keybinds).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => m.button === Qt.RightButton ? Notify.toggleDnd() : Notify.toggleHistory()
    }

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: (Notify.dnd ? "Do-not-disturb ON" : count + " notification" + (count === 1 ? "" : "s"))
            + " · click: history · right-click: DND"
    }
}
