// CalendarPill — sits beside Clock. Shows today's date; click opens
// CalendarPanel (month view + today's entries). Entries are local-only for
// now (calendar.json via PanelBus); the JSON shape already matches what a
// CalDAV source would hand back, so plugging one in later is a source swap,
// not a view rewrite.
import QtQuick
import "../../services"   // Theme
import "CalendarSource.js" as CalendarSource

Text {
    id: root
    property string screenName: ""

    readonly property var _clock: SystemClock { precision: SystemClock.Minute }
    readonly property string today: Qt.formatDate(_clock.date, "yyyy-MM-dd")
    readonly property int todayCount: CalendarSource.entriesOn(PanelBus.calendarEntries, root.today).length

    color: hover.hovered ? Theme.text : Theme.c.pink
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: Theme.space.md; rightPadding: Theme.space.md
    text: "" + Qt.formatDate(_clock.date, "dd MMM") + (root.todayCount > 0 ? " ·" + root.todayCount : "")

    MouseArea {
        anchors.fill: parent
        onClicked: PanelBus.toggle("calendar", root.screenName, root.mapToItem(null, root.width / 2, 0).x)
    }

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: root.todayCount > 0
            ? root.todayCount + " entr" + (root.todayCount === 1 ? "y" : "ies") + " today · click to open"
            : "No entries today · click to open"
    }
}
