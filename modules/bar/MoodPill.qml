// MoodPill — bar entry for the mood centre (LEO-237). Shows the active mood
// (accent while running, dim in neutral) with the time left when timed, and
// click opens MoodPanel via PanelBus — the same single-window pattern as
// CalendarPill. Read-only over Focus's own state: the mood, the timer, the
// policy all live in the focus/mood-policy stores this pill only mirrors.
import Quickshell
import QtQuick
import "../../services"   // Theme, Focus, PanelBus

Text {
    id: root
    property string screenName: ""

    // Ticks once a second so `remaining` counts down without polling anything.
    readonly property var _clock: SystemClock { precision: SystemClock.Seconds }

    readonly property bool running: Focus.mode !== "neutral"
    readonly property string remaining: {
        root._clock.date;   // dependency: recompute every tick
        if (!root.running || !Focus.until) return "";
        const ms = Date.parse(Focus.until) - Date.now();
        if (ms <= 0) return "";
        const m = Math.ceil(ms / 60000);
        return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m";
    }

    color: root.running ? Theme.accent : hover.hovered ? Theme.text : Theme.c.subtext1
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: Theme.space.md; rightPadding: Theme.space.md
    text: (root.running ? Focus.current.name : "neutral")
        + (root.remaining ? " · " + root.remaining : "")

    MouseArea {
        anchors.fill: parent
        onClicked: PanelBus.toggle("mood", root.screenName, root.mapToItem(null, root.width / 2, 0).x)
    }

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: root.running
            ? Focus.current.name + " on" + (root.remaining ? " · " + root.remaining + " left" : " · open-ended") + " · click to configure"
            : "neutral · click to configure"
    }
}