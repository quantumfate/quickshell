// FocusPill — bar pill for services/Focus.qml. Shows the active mood and,
// while timed, the time left; click cycles neutral <-> deep (the two ends of
// "off"/"on" from a single pill — every other mood is a deliberate pick via
// `ipc call focus set <mood>`, not a click-through). Read-only over Focus's
// own state — no store of its own.
import Quickshell
import QtQuick
import "../../services"   // Theme, Focus

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

    color: root.running ? Theme.accent : hover.hovered ? Theme.text : Theme.c.overlay1
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: Theme.space.md; rightPadding: Theme.space.md
    text: (root.running ? "" : "") + (root.remaining ? " " + root.remaining : "")

    MouseArea {
        anchors.fill: parent
        onClicked: root.running ? Focus.stop() : Focus.set("deep", 0)
    }

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: root.running
            ? Focus.current.name + " on" + (root.remaining ? " · " + root.remaining + " left" : " · open-ended") + " · click to stop"
            : "Neutral · click to start deep work"
    }
}
