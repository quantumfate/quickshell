// SysPanel — the system-monitor detail popout. A single window driven by the
// SysMon bus: it appears below the bar on whichever screen is peeking or pinned,
// anchored under the cluster. Read-only, so it stays a passive overlay (no
// focus, click-through) even when pinned.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // SysStats, SysMon, Theme

Scope {
    id: scope

    PanelWindow {
        visible: SysMon.shown
        screen: Quickshell.screens.find(s => s.name === SysMon.activeScreen) ?? null
        color: "transparent"

        anchors { top: true; left: true; right: true }
        margins { top: 32 }
        implicitHeight: card.implicitHeight

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusiveZone: 0
        mask: Region { item: card }

        Rectangle {
            id: card
            // Centre under the cluster, clamped on-screen.
            x: Math.max(6, Math.min(SysMon.anchorX - width / 2, parent.width - width - 6))
            y: 0
            width: 320
            implicitHeight: content.implicitHeight + 24
            radius: Theme.radiusPill
            color: Theme.withAlpha(Theme.backgroundAlt, 0.98)
            border { width: 1; color: SysMon.pinned ? Theme.accent : Theme.border }

            ColumnLayout {
                id: content
                anchors { fill: parent; margins: 12 }
                spacing: 12

                // ---- CPU ----
                Section {
                    label: "CPU"; tint: Theme.c.lavender
                    value: SysStats.cpuPct + "%"
                    sub: SysStats.cpuCores + " cores · load " + SysStats.loadAvg
                    ratio: SysStats.cpuPct / 100
                    history: SysStats.cpuHistory; historyMax: 100
                }
                // ---- Memory ----
                Section {
                    label: "Memory"; tint: Theme.c.blue
                    value: SysStats.memUsedG.toFixed(1) + " / " + SysStats.memTotalG.toFixed(1) + "G"
                    sub: SysStats.swapTotalG > 0
                        ? SysStats.memPct + "% · swap " + SysStats.swapUsedG.toFixed(1) + "G"
                        : SysStats.memPct + "%"
                    ratio: SysStats.memPct / 100
                }
                // ---- GPU (NVIDIA only) ----
                Section {
                    visible: SysStats.gpuPresent
                    label: "GPU"; tint: Theme.c.green
                    value: SysStats.gpuPct + "%"
                    sub: SysStats.gpuTemp + "°C · " + SysStats.gpuMemUsedG.toFixed(1)
                        + " / " + SysStats.gpuMemTotalG.toFixed(1) + "G"
                    ratio: SysStats.gpuPct / 100
                    history: SysStats.gpuHistory; historyMax: 100
                }
                // ---- Disk ----
                Section {
                    label: "Disk /"; tint: Theme.c.sapphire
                    value: SysStats.diskFree + " free"
                    sub: SysStats.diskUsedPct + " used"
                    ratio: (parseInt(SysStats.diskUsedPct) || 0) / 100
                }
                // ---- Network ----
                Section {
                    label: SysStats.wifiSignal >= 0 ? "Wi-Fi" : "Network"; tint: Theme.c.sky
                    value: SysStats.wifiSsid || SysStats.netState
                    sub: "󰇚 " + SysStats.fmtRate(SysStats.rxRate) + "   󰕒 " + SysStats.fmtRate(SysStats.txRate)
                        + (SysStats.wifiSignal >= 0 ? "   󰢾 " + SysStats.wifiSignal + "%" : "")
                    history: SysStats.rxHistory
                    historyMax: Math.max(1, ...SysStats.rxHistory, ...SysStats.txHistory)
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: "up " + SysStats.uptime + (SysMon.pinned ? "  · pinned" : "")
                    color: Theme.overlay
                    font { family: Theme.fontFamily; pixelSize: 10 }
                }
            }
        }
    }

    // One labelled stat block: header row, a progress meter, optional sparkline.
    component Section: ColumnLayout {
        id: sec
        property string label: ""
        property string value: ""
        property string sub: ""
        property color tint: Theme.text
        property real ratio: 0                 // 0..1 meter fill
        property var history: null             // optional sparkline samples
        property real historyMax: 100
        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: sec.label; color: sec.tint
                font { family: Theme.fontFamily; pixelSize: 11; weight: Font.Bold; capitalization: Font.AllUppercase }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: sec.value; color: Theme.text
                font { family: Theme.fontFamily; pixelSize: 13; weight: Theme.barFontWeight }
            }
        }

        // Meter.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 4; radius: 2
            color: Theme.surface
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, sec.ratio))
                height: parent.height; radius: 2
                color: sec.tint
            }
        }

        Text {
            visible: !!sec.sub
            text: sec.sub; color: Theme.subtext
            font { family: Theme.fontFamily; pixelSize: 11 }
        }

        // Sparkline (optional).
        Canvas {
            visible: sec.history && sec.history.length > 1
            Layout.fillWidth: true
            implicitHeight: visible ? 26 : 0
            readonly property var pts: sec.history || []
            readonly property real maxV: sec.historyMax
            readonly property color stroke: sec.tint
            onPtsChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const n = pts.length;
                if (n < 2) return;
                const w = width, h = height, mx = Math.max(1, maxV);
                ctx.beginPath();
                for (let i = 0; i < n; i++) {
                    const x = (i / (n - 1)) * w;
                    const y = h - (Math.max(0, Math.min(mx, pts[i])) / mx) * (h - 2) - 1;
                    i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
                }
                ctx.strokeStyle = stroke;
                ctx.lineWidth = 1.5;
                ctx.stroke();
            }
        }
    }
}
