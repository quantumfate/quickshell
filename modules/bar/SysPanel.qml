// SysPanel — the bar's on-demand System Center (LEO-221). A single window
// driven by the SysMon bus, opened via `qs ipc call sysmon toggle` / which-key
// rather than a bar trigger: the persistent bar is a status indicator now,
// not a place for system info, background apps, logout, or diagnostics to
// live always-on. Read-only sections stay a passive overlay (no focus,
// click-through) even when pinned; the quick-control chips and the
// background-apps row at the bottom are the exception — every module that
// used to sit permanently on the bar (weather, power profile, idle inhibit,
// language, tray, battery, notifications, projects health, focus mode,
// logout, the Dofus submap name, the Dofus swap-detector rig) collapsed into
// this one popout.
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import "../../services"   // SysStats, SysMon, Theme
import "../common"        // Surface

Scope {
    id: scope

    PanelWindow {
        id: win
        visible: SysMon.shown
        screen: PanelBus.screenObject(SysMon.activeScreen)
        color: "transparent"

        anchors { top: true; left: true; right: true }
        implicitHeight: card.implicitHeight

        WlrLayershell.layer: WlrLayer.Overlay

        // Named so the compositor can frost it like the rest of the shell.

        WlrLayershell.namespace: "quickshell-syspanel"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusiveZone: 0
        mask: Region { item: card }

        readonly property string _screenName: win.screen?.name ?? ""
        // Placed in the scene's published work area (docs/scenes.md
        // "Areas"): the top margin and the horizontal clamp both come from
        // the area now, instead of a fixed `Theme.barReserved` strip, so the
        // panel can never sit under a bar. The card still centres itself
        // under the cluster (`SysMon.anchorX`) within those bounds.
        readonly property var _box: PanelBus.surfaceBox(win._screenName, "sysmon", { width: 340, height: card.implicitHeight })
        margins { top: win._box.y }

        Surface {
            id: card
            // Centre under the cluster, clamped to the placed area.
            x: Math.max(win._box.x, Math.min(SysMon.anchorX - width / 2, win._box.x + win._box.width - width))
            y: 0
            width: 340
            implicitHeight: content.implicitHeight + 24
            elevation: "peek"
            radius: Theme.radiusPill
            border { width: 1; color: SysMon.pinned ? Theme.accent : Theme.withAlpha(Theme.border, 0.45) }

            ColumnLayout {
                id: content
                anchors { fill: parent; margins: Theme.space.lg }
                spacing: Theme.space.lg

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

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                // ---- Quick controls: what SysMonitor/Weather/Brightness/
                // PowerProfile/IdleInhibit/Language used to carry as five
                // separate always-on bar entries. ----
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.space.sm

                    QuickChip {
                        glyph: "weather"; text: weather.value; tint: Theme.c.sky
                        onTapped: weather.openForecast()
                    }
                    QuickChip {
                        glyph: "power"; text: power.label; tint: power.tint
                        visible: PowerProfiles.hasPerformanceProfile
                        onTapped: power.cycle()
                    }
                    QuickChip {
                        glyph: "idle"; text: idle.active ? "awake" : "auto"; tint: idle.active ? Theme.success : Theme.overlay
                        onTapped: idle.toggle()
                    }
                    QuickChip {
                        glyph: "lang"; text: language.value; tint: Theme.c.overlay1
                        onTapped: language.cycle()
                    }
                    // Dofus swap-detector rig (formerly SwapControl.qml on the
                    // bar) — on demand, not gated to any one workspace anymore.
                    QuickChip {
                        glyph: "calib"; text: DofusSwap.calibrated ? "ready" : "calibrate"
                        tint: DofusSwap.calibrating ? Theme.accent : DofusSwap.calibrated ? Theme.success : Theme.warning
                        onTapped: DofusSwap.calibrate()
                    }
                    QuickChip {
                        glyph: "swap"; text: DofusSwap.detectorRunning ? "running" : "stopped"
                        tint: DofusSwap.detectorRunning ? Theme.success : Theme.subtext
                        onTapped: DofusSwap.toggle()
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                // ---- Background apps / diagnostics: the always-on bar entries
                // the persistent bar shed. The notification bell and the power
                // button moved back out to the bar's right isle (LEO-425) —
                // they are glance-and-act entries, not panel content. ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.lg

                    Tray {}
                    Item { Layout.fillWidth: true }
                    Submap {}
                    ModePill { screenName: SysMon.activeScreen }
                    ProjectsPill { screenName: SysMon.activeScreen }
                    Battery { screenName: SysMon.activeScreen }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: "up " + SysStats.uptime + (SysMon.pinned ? "  · pinned" : "")
                    color: Theme.overlay
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                }
            }
        }
    }

    // ---- Ported state for the quick-control chips (formerly one bar module
    // each: Weather.qml, Brightness.qml, PowerProfile.qml, IdleInhibit.qml,
    // Language.qml). Non-visual; only polled while the panel exists, which is
    // always (the Scope is instantiated once), matching the old modules'
    // always-on polling. ----

    Item {
        id: weather
        property string value: ""
        function openForecast() { weatherOpen.running = true; }
        Process {
            id: weatherOpen
            command: ["bash", "-lc", "xdg-open 'https://wttr.in' >/dev/null 2>&1"]
        }
        Process {
            id: weatherFetch
            command: ["bash", "-lc",
                "curl -sf --max-time 10 'https://wttr.in/?format=%c+%t' 2>/dev/null | tr -d '+' | grep . || true"]
            stdout: StdioCollector { onStreamFinished: weather.value = (this.text || "").trim() }
        }
        Timer {
            interval: 900000   // 15 min — weather doesn't move faster than that
            running: true; repeat: true; triggeredOnStart: true
            onTriggered: if (!weatherFetch.running) weatherFetch.running = true
        }
    }

    Item {
        id: power
        readonly property int profile: PowerProfiles.profile
        readonly property string label: profile === PowerProfile.Performance ? "perf"
            : profile === PowerProfile.PowerSaver ? "saver" : "balanced"
        readonly property color tint: profile === PowerProfile.Performance ? Theme.c.red
            : profile === PowerProfile.PowerSaver ? Theme.c.green : Theme.c.sapphire
        function cycle() {
            PowerProfiles.profile = profile === PowerProfile.PowerSaver ? PowerProfile.Balanced
                : profile === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile ? PowerProfile.Performance
                : PowerProfile.PowerSaver;
        }
    }

    Item {
        id: idle
        property bool active: false
        function refresh() { if (!idleReader.running) idleReader.running = true; }
        function toggle() {
            idleAction.command = ["bash", "-lc",
                "if systemctl --user is-active --quiet quickshell-idle-inhibit; then "
                + "systemctl --user stop quickshell-idle-inhibit; "
                + "else systemd-run --user --unit=quickshell-idle-inhibit --collect "
                + "systemd-inhibit --what=idle --mode=block --who=quickshell --why='idle inhibitor toggle' sleep infinity; fi"];
            idleAction.running = true;
            refresh();
        }
        Process { id: idleAction }
        Process {
            id: idleReader
            command: ["bash", "-lc", "systemctl --user is-active quickshell-idle-inhibit || true"]
            stdout: StdioCollector { onStreamFinished: idle.active = (this.text || "").trim() === "active" }
        }
        Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: idle.refresh() }
    }

    Item {
        id: language
        property string value: ""
        function cycle() { languageAction.running = true; refresh(); }
        function refresh() { if (!languageFetch.running) languageFetch.running = true; }
        Process { id: languageAction; command: ["hyprctl", "switchxkblayout", "all", "next"] }
        Process {
            id: languageFetch
            command: ["bash", "-lc", "$HOME/.config/waybar/scripts/language.sh"]
            stdout: StdioCollector { onStreamFinished: language.value = (this.text || "").trim() }
        }
        Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: language.refresh() }
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
        spacing: Theme.space.sm

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: sec.label; color: sec.tint
                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: Font.Bold; capitalization: Font.AllUppercase }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: sec.value; color: Theme.text
                font { family: Theme.fontFamily; pixelSize: Theme.fs.md; weight: Theme.barFontWeight }
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
            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
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

    // A small labelled control chip: glyph + value, tap and (optional) scroll.
    component QuickChip: Rectangle {
        id: chip
        property string glyph: ""
        property string text: ""
        property color tint: Theme.text
        signal tapped()
        signal wheelUp()
        signal wheelDown()

        implicitWidth: chipRow.implicitWidth + Theme.space.md * 2
        implicitHeight: chipRow.implicitHeight + Theme.space.sm * 2
        radius: Theme.radiusSmall
        color: chipHover.hovered ? Theme.surfaceAlt : Theme.surface
        border { width: 1; color: Theme.border }

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Theme.space.sm
            Text {
                text: chip.glyph.toUpperCase()
                color: chip.tint
                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: Font.Bold }
            }
            Text {
                visible: !!chip.text
                text: chip.text
                color: Theme.text
                font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
            }
        }

        HoverHandler { id: chipHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.tapped()
            onWheel: (w) => w.angleDelta.y > 0 ? chip.wheelUp() : chip.wheelDown()
        }
    }
}
