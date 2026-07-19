// Used RAM in GiB, from /proc/meminfo (waybar memory, format "{used:0.1f}G").
// Used = MemTotal - MemAvailable, matching what waybar reports.
import QtQuick
import Quickshell.Io
import "../../services"   // Theme

Text {
    id: root
    color: Theme.c.blue
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: 10; rightPadding: 10
    text: "--G "

    // Pull a "Key:  N kB" value out of /proc/meminfo, in kB.
    function _kb(text, key) {
        const m = text.match(new RegExp("^" + key + ":\\s+(\\d+)", "m"));
        return m ? Number(m[1]) : 0;
    }

    FileView { id: mem; path: "/proc/meminfo" }
    Timer {
        interval: 10000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            mem.reload();
            const t = mem.text() || "";
            const usedKb = root._kb(t, "MemTotal") - root._kb(t, "MemAvailable");
            root.text = (usedKb / 1048576).toFixed(1) + "G ";
        }
    }
}
