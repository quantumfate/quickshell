// PollText — a bar label backed by a shell command re-run on an interval.
// The waybar `custom/*` exec model: run `command`, show its trimmed stdout,
// optionally fire `clickCommand` / scroll commands on interaction.
import QtQuick
import Quickshell.Io
import "../../services"   // Theme

Text {
    id: root

    // Shell command whose stdout becomes the label (run via `bash -lc`).
    property string command: ""
    property int intervalMs: 5000

    // Optional side-effect commands; empty string disables the gesture.
    property string clickCommand: ""
    property string scrollUpCommand: ""
    property string scrollDownCommand: ""

    color: Theme.subtext
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    verticalAlignment: Text.AlignVCenter
    leftPadding: 10; rightPadding: 10

    // Reads the label. Re-armed by the Timer; guarded so slow commands can't
    // overlap themselves.
    Process {
        id: reader
        command: ["bash", "-lc", root.command]
        stdout: StdioCollector { onStreamFinished: root.text = (this.text || "").trim() }
    }
    Timer {
        interval: root.intervalMs; running: root.command !== ""
        repeat: true; triggeredOnStart: true
        onTriggered: if (!reader.running) reader.running = true
    }

    // Fire-and-forget for click/scroll side effects.
    Process { id: action }
    function _fire(cmd) { if (cmd) { action.command = ["bash", "-lc", cmd]; action.running = true; } }

    MouseArea {
        anchors.fill: parent
        enabled: root.clickCommand || root.scrollUpCommand || root.scrollDownCommand
        onClicked: root._fire(root.clickCommand)
        onWheel: (w) => root._fire(w.angleDelta.y > 0 ? root.scrollUpCommand : root.scrollDownCommand)
    }
}
