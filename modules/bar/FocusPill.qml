// FocusPill — bar pill for services/Focus.qml. Shows the current mode and,
// while running, the time left; click toggles it (same effect as
// `ipc call focus start/stop`). Read-only over Focus's own state — no store
// of its own.
import Quickshell
import QtQuick
import "../../services"   // Theme, Focus

Text {
    id: root
    property string screenName: ""

    // Ticks once a second so `remaining` counts down without polling anything.
    readonly property var _clock: SystemClock { precision: SystemClock.Seconds }

    readonly property bool running: Focus.mode === "focus"
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
        onClicked: root.running ? Focus.stop() : Focus.start(0)
    }

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: root.running
            ? "Focus mode on" + (root.remaining ? " · " + root.remaining + " left" : " · open-ended") + " · click to stop"
            : "Focus mode off · click to start"
    }
}
