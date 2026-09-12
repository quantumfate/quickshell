// IdleInhibit — "keep awake" toggle (waybar custom/idle_inhibitor).
// Active ⇒ hypridle's idle listeners (dim, screen off, auto-lock, suspend) are
// suppressed until toggled off again. Backed by a transient user unit holding
// a systemd-inhibit --what=idle lock, so the state survives bar restarts and
// is still released if the session's systemd dies.
import QtQuick
import Quickshell.Io
import "../../services"   // Theme, Tip

Text {
    id: root

    property string screenName: ""
    property bool _active: false
    readonly property bool active: root._active

    color: root.active ? Theme.c.green : Theme.c.overlay1
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: 10; rightPadding: 10

    // eye / eye-slash: idle running normally vs. inhibited.
    text: (root.active ? " \uf070" : " \uf06e")

    function _refresh() {
        if (!reader.running) reader.running = true;
    }

    Process {
        id: reader
        command: ["bash", "-lc", "systemctl --user is-active quickshell-idle-inhibit || true"]
        stdout: StdioCollector {
            onStreamFinished: root._active = (this.text || "").trim() === "active"
        }
    }
    Timer {
        interval: 3000; repeat: true; triggeredOnStart: true
        onTriggered: root._refresh()
    }

    // Fire-and-forget toggle: start the transient inhibitor unit if stopped,
    // stop it if running.
    Process { id: action }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            action.command = ["bash", "-lc",
                "if systemctl --user is-active --quiet quickshell-idle-inhibit; then "
                + "systemctl --user stop quickshell-idle-inhibit; "
                + "else systemd-run --user --unit=quickshell-idle-inhibit --collect "
                + "systemd-inhibit --what=idle --mode=block --who=quickshell --why='idle inhibitor toggle' sleep infinity; fi"];
            action.running = true;
            root._refresh();
        }
    }

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: root.active ? "Idle inhibit ON · click to release"
                          : "Idle inhibit OFF · click to keep awake"
    }
}