pragma Singleton
// SysStats — one place that samples the machine: CPU load, memory, swap, disk,
// network throughput + wifi, load average and uptime. The compact bar cluster
// (SysMonitor) and its hover/pinned detail panel (SysPanel) both read from here,
// so there's a single sampling path instead of four independent widgets.
//
// Fast stats come straight from /proc (cheap, no subprocess); disk and wifi —
// which need tools — poll on a slower cadence via one shell call each.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // ---- CPU ---------------------------------------------------------------
    property int cpuPct: 0
    property int cpuCores: 0
    property var cpuHistory: []          // rolling cpuPct samples for a sparkline
    readonly property int _histLen: 40
    property double _prevTotal: 0
    property double _prevIdle: 0

    // ---- memory ------------------------------------------------------------
    property real memUsedG: 0
    property real memTotalG: 0
    property real swapUsedG: 0
    property real swapTotalG: 0
    readonly property int memPct: memTotalG > 0 ? Math.round(100 * memUsedG / memTotalG) : 0

    // ---- load / uptime -----------------------------------------------------
    property string loadAvg: "—"
    property string uptime: "—"

    // ---- network -----------------------------------------------------------
    property string netIface: ""
    property string wifiSsid: ""
    property int wifiSignal: -1          // 0..100, -1 when unknown/wired
    property string netState: "Disconnected"
    property real rxRate: 0              // bytes/sec
    property real txRate: 0
    property var rxHistory: []
    property var txHistory: []
    property double _prevRx: 0
    property double _prevTx: 0
    property double _prevNetT: 0

    // ---- disk --------------------------------------------------------------
    property string diskFree: "—"
    property string diskUsedPct: "—"

    // ---- GPU (NVIDIA via nvidia-smi; absent → gpuPresent stays false) -------
    property bool gpuPresent: false
    property int gpuPct: 0
    property int gpuTemp: 0
    property real gpuMemUsedG: 0
    property real gpuMemTotalG: 0
    property var gpuHistory: []

    // Human "12.4 MB/s" from a bytes/sec rate.
    function fmtRate(bps) {
        if (bps < 1024) return Math.round(bps) + " B/s";
        if (bps < 1048576) return (bps / 1024).toFixed(0) + " KB/s";
        return (bps / 1048576).toFixed(1) + " MB/s";
    }
    function _push(arr, v) {
        const a = arr.concat([v]);
        return a.length > root._histLen ? a.slice(a.length - root._histLen) : a;
    }

    // Fast path: CPU + memory + load + net counters, straight from /proc.
    FileView { id: stat; path: "/proc/stat" }
    FileView { id: meminfo; path: "/proc/meminfo" }
    FileView { id: loadavg; path: "/proc/loadavg" }
    FileView { id: netdev; path: "/proc/net/dev" }
    FileView { id: uptimeF; path: "/proc/uptime" }

    function _kb(text, key) {
        const m = text.match(new RegExp("^" + key + ":\\s+(\\d+)", "m"));
        return m ? Number(m[1]) : 0;
    }

    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root._sampleFast()
    }
    function _sampleFast() {
        // CPU
        stat.reload();
        const st = stat.text() || "";
        const line = st.split("\n")[0];
        if (line.startsWith("cpu")) {
            const f = line.trim().split(/\s+/).slice(1).map(Number);
            const total = f.reduce((a, b) => a + b, 0);
            const idle = f[3] + (f[4] || 0);
            const dt = total - root._prevTotal, di = idle - root._prevIdle;
            if (root._prevTotal > 0 && dt > 0) {
                root.cpuPct = Math.round(100 * (dt - di) / dt);
                root.cpuHistory = root._push(root.cpuHistory, root.cpuPct);
            }
            root._prevTotal = total; root._prevIdle = idle;
            root.cpuCores = (st.match(/^cpu\d+ /gm) || []).length;
        }

        // memory + swap
        meminfo.reload();
        const mt = meminfo.text() || "";
        const totalKb = root._kb(mt, "MemTotal");
        root.memUsedG = (totalKb - root._kb(mt, "MemAvailable")) / 1048576;
        root.memTotalG = totalKb / 1048576;
        const swTotal = root._kb(mt, "SwapTotal");
        root.swapTotalG = swTotal / 1048576;
        root.swapUsedG = (swTotal - root._kb(mt, "SwapFree")) / 1048576;

        // load average (1-minute)
        loadavg.reload();
        root.loadAvg = (loadavg.text() || "").trim().split(/\s+/).slice(0, 3).join(" ") || "—";

        // uptime
        uptimeF.reload();
        const up = Number((uptimeF.text() || "0").trim().split(/\s+/)[0]);
        const d = Math.floor(up / 86400), h = Math.floor((up % 86400) / 3600), m = Math.floor((up % 3600) / 60);
        root.uptime = (d > 0 ? d + "d " : "") + h + "h " + m + "m";

        // network throughput over the active iface (from /proc/net/dev)
        netdev.reload();
        const now = Date.now() / 1000;
        const iface = root.netIface;
        let rx = 0, tx = 0, found = false;
        for (const l of (netdev.text() || "").split("\n")) {
            const m = l.match(/^\s*([\w-]+):\s+(\d+)(?:\s+\d+){7}\s+(\d+)/);
            if (!m) continue;
            if (iface ? m[1] === iface : m[1] !== "lo") { rx += Number(m[2]); tx += Number(m[3]); found = true; if (iface) break; }
        }
        if (found && root._prevNetT > 0) {
            const dts = now - root._prevNetT;
            if (dts > 0) {
                root.rxRate = Math.max(0, (rx - root._prevRx) / dts);
                root.txRate = Math.max(0, (tx - root._prevTx) / dts);
                root.rxHistory = root._push(root.rxHistory, root.rxRate);
                root.txHistory = root._push(root.txHistory, root.txRate);
            }
        }
        root._prevRx = rx; root._prevTx = tx; root._prevNetT = now;
    }

    // Slow path: disk + wifi + active iface — need userspace tools, so one shell
    // call each on a relaxed cadence. TAB-joined fields, parsed below.
    Process {
        id: probe
        command: ["bash", "-lc",
            "printf '%s\\t%s\\t%s\\t' " +
            "\"$(df -h --output=avail / | tail -1 | tr -d ' ')\" " +
            "\"$(df -h --output=pcent / | tail -1 | tr -d ' ')\" " +
            "\"$(ip route show default 2>/dev/null | awk '{print $5; exit}')\"; " +
            "nmcli -t -f ACTIVE,SSID,SIGNAL,DEVICE dev wifi 2>/dev/null | awk -F: '$1==\"yes\"{print $2\"\\t\"$3\"\\t\"$4; exit}'; " +
            "printf '\\n'; " +
            "nmcli -t -f NAME connection show --active 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: root._parseProbe(this.text || "")
        }
    }
    Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!probe.running) probe.running = true
    }
    // GPU: one nvidia-smi query on the fast cadence (util moves quickly). Emits
    // "util, temp, memUsedMiB, memTotalMiB"; empty when no NVIDIA GPU.
    Process {
        id: gpuProbe
        command: ["bash", "-lc",
            "nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total " +
            "--format=csv,noheader,nounits 2>/dev/null | head -1 || true"]
        stdout: StdioCollector { onStreamFinished: root._parseGpu(this.text || "") }
    }
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!gpuProbe.running) gpuProbe.running = true
    }
    function _parseGpu(text) {
        const f = (text || "").trim().split(",").map(x => Number(x));
        if (f.length < 4 || isNaN(f[0])) { root.gpuPresent = false; return; }
        root.gpuPresent = true;
        root.gpuPct = f[0];
        root.gpuTemp = f[1];
        root.gpuMemUsedG = f[2] / 1024;
        root.gpuMemTotalG = f[3] / 1024;
        root.gpuHistory = root._push(root.gpuHistory, root.gpuPct);
    }

    function _parseProbe(text) {
        const lines = (text || "").split("\n");
        const a = (lines[0] || "").split("\t");
        root.diskFree = a[0] || "—";
        root.diskUsedPct = a[1] || "—";
        if (a[2]) root.netIface = a[2];
        // wifi ssid/signal/device (only present on a wifi connection)
        root.wifiSsid = a[3] || "";
        root.wifiSignal = a[4] !== undefined && a[4] !== "" ? Number(a[4]) : -1;
        root.netState = (lines[1] || "").trim() || "Disconnected";
    }
}
