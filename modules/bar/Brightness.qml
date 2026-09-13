// Brightness — bar centre control (04-persistent-bar.md). Polls the same
// `,brightness.sh` used by the old SysPanel quick-chip; promoted here because
// the spec puts brightness in the always-visible transport zone, not behind
// a hover panel.
import QtQuick
import Quickshell.Io

MeterControl {
    id: root
    glyph: ""
    screenName: ""
    tip: "Scroll to adjust brightness"

    property int pct: 0
    ratio: root.pct / 100
    valueText: root.pct > 0 ? root.pct + "%" : ""

    function step(up) {
        action.command = ["bash", "-lc", up ? ",brightness.sh --inc" : ",brightness.sh --dec"];
        action.running = true;
        Qt.callLater(refresh);
    }
    function refresh() { if (!fetch.running) fetch.running = true; }

    onTapped: {}
    onWheelUp: root.step(true)
    onWheelDown: root.step(false)

    Process { id: action }
    Process {
        id: fetch
        command: ["bash", "-lc", ",brightness.sh --get"]
        stdout: StdioCollector {
            onStreamFinished: root.pct = parseInt((this.text || "0").trim()) || 0
        }
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
