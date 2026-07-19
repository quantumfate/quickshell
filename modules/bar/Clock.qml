// Clock bar module: a teal surface pill with the time, ticking each second.
import QtQuick
import Quickshell
import "../../services"   // Theme

Rectangle {
    id: clock
    color: Theme.c.surface0
    radius: Theme.radiusPill
    implicitWidth: label.implicitWidth + 28
    implicitHeight: 22

    readonly property var _clock: SystemClock { precision: SystemClock.Seconds }

    Text {
        id: label
        anchors.centerIn: parent
        text: Qt.formatDateTime(clock._clock.date, "ddd dd MMM  hh:mm:ss")
        color: Theme.c.teal
        font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Font.Bold }
    }
}
