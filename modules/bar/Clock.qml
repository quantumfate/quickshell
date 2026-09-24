// Clock bar module: the date and time, ticking each second, with today's
// calendar entry count folded in (LEO-425 — the standalone date chip is gone).
// Click opens the calendar panel, anchored to this isle's live dock position
// like every other bar-triggered panel.
import QtQuick
import Quickshell
import "../../services"   // Theme, PanelBus
import "CalendarSource.js" as CalendarSource

Text {
    id: root
    property string screenName: ""

    readonly property var _clock: SystemClock { precision: SystemClock.Seconds }
    readonly property string today: Qt.formatDate(_clock.date, "yyyy-MM-dd")
    readonly property int todayCount: CalendarSource.entriesOn(PanelBus.calendarEntries, root.today).length

    color: hover.hovered ? Theme.text : Theme.c.teal
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Font.Bold }
    leftPadding: Theme.space.md; rightPadding: Theme.space.md
    text: Qt.formatDateTime(root._clock.date, "ddd dd MMM  hh:mm:ss")
        + (root.todayCount > 0 ? " ·" + root.todayCount : "")

    MouseArea {
        anchors.fill: parent
        onClicked: PanelBus.toggle("calendar", root.screenName, root.mapToItem(null, root.width / 2, 0).x, "bar.clock")
    }

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: root.todayCount > 0
            ? root.todayCount + " entr" + (root.todayCount === 1 ? "y" : "ies") + " today · click to open"
            : "No entries today · click to open"
    }
}
