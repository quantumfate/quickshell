// CPU usage %, from the delta of two /proc/stat samples (waybar cpu).
// Kept dependency-free: the busy/total jiffy deltas between polls give load.
import QtQuick
import Quickshell.Io
import "../../services"   // Theme

Text {
    id: root
    color: Theme.c.lavender
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: 10; rightPadding: 10
    text: "--% "

    // Previous sample's cumulative jiffies, to diff against the next read.
    property double _prevTotal: 0
    property double _prevIdle: 0

    // Sums total + idle jiffies from the aggregate `cpu` line of /proc/stat.
    function _sample(line) {
        const f = line.trim().split(/\s+/).slice(1).map(Number);   // drop "cpu" label
        const total = f.reduce((a, b) => a + b, 0);
        const idle = f[3] + (f[4] || 0);                            // idle + iowait
        return { total, idle };
    }

    FileView { id: stat; path: "/proc/stat" }
    Timer {
        interval: 4000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            stat.reload();
            const line = (stat.text() || "").split("\n")[0];
            if (!line.startsWith("cpu")) return;
            const s = root._sample(line);
            const dt = s.total - root._prevTotal;
            const di = s.idle - root._prevIdle;
            if (root._prevTotal > 0 && dt > 0)
                root.text = Math.round(100 * (dt - di) / dt) + "% ";
            root._prevTotal = s.total; root._prevIdle = s.idle;
        }
    }
}
