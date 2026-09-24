// CalendarPanel — calendar center. Three stacked regions (06-widgets.md
// §6.5): today's timeline, an upcoming list (the focus mode each
// event implies is disabled — CalendarSource.impliedMode always returns
// null, so the mode chip and Enter-to-adopt both stay dormant), and a
// collapsed month grid. Opened from the bar's clock (LEO-425), same
// PanelBus-driven single-window pattern as ProjectsDashboard/SysPanel.
//
// Adopting a mode from Upcoming shells out to the `focus` IPC target
// (services/Focus.qml's `set(mode, minutes)`) rather than importing the
// singleton directly, so this panel never depends on Focus.qml's shape
// beyond its IPC contract.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, PanelBus
import "../common"        // Surface
import "CalendarSource.js" as CalendarSource

Scope {
    id: scope

    readonly property var _clock: SystemClock { precision: SystemClock.Minutes }
    readonly property string todayIso: Qt.formatDate(scope._clock.date, "yyyy-MM-dd")
    readonly property string nowTime: Qt.formatTime(scope._clock.date, "hh:mm")

    // The month grid's own view/cursor, independent of `todayIso` so
    // browsing away from today doesn't lose today's highlight.
    property int viewYear: scope._clock.date.getFullYear()
    property int viewMonth: scope._clock.date.getMonth()
    property string cursorDate: scope.todayIso

    property bool monthExpanded: false
    // "upcoming" | "month" — which region h/j/k/l and Enter act on.
    property string focusRegion: "upcoming"
    property int upcomingIndex: 0

    readonly property var grid: CalendarSource.monthGrid(scope.viewYear, scope.viewMonth)
    readonly property var counts: CalendarSource.countsByDate(PanelBus.calendarEntries)
    readonly property var todayEntries: CalendarSource.entriesOn(PanelBus.calendarEntries, scope.todayIso)
    readonly property var upcomingEntries: CalendarSource.upcoming(PanelBus.calendarEntries, scope.todayIso, scope.nowTime, 5)
    readonly property var freeBlocks: CalendarSource.freeBlocks(scope.todayEntries, 6, 24)

    // Per-calendar mode defaults, part of the (disabled)
    // CalendarSource.impliedMode contract — kept so a future re-enable needs
    // no caller-side rewrite here.
    readonly property var calendarModeDefaults: ({})

    function moveCursor(days) {
        scope.cursorDate = CalendarSource.addDays(scope.cursorDate, days);
        const ym = CalendarSource.ymOf(scope.cursorDate);
        scope.viewYear = ym.year;
        scope.viewMonth = ym.month;
    }

    function jumpToDay(dayOfMonth) {
        scope.cursorDate = CalendarSource.isoDate(scope.viewYear, scope.viewMonth, dayOfMonth);
    }

    // Adopts the mode an event implies via the `focus` IPC target
    // (services/Focus.qml's `set(mode, minutes)`), open-ended (0 minutes) —
    // this is "switch the desk into this mood now", not a timer.
    Process { id: adoptProc }

    // Weather context (LEO-225), LOCAL SOURCE FIRST: the desk's own store
    // (QF_STORE/weather.json — provisioning's task to fill, never the panel's
    // network call). A missing or unreadable store renders quietly — the
    // same empty-is-not-an-error rule the calendar entries keep.
    property var weatherReport: ({})
    FileView {
        id: weatherFile
        path: Config.stateDir + "/weather.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse((text() || "{}"));
                scope.weatherReport = (parsed && parsed.temp_c !== undefined && parsed.observed_at) ? parsed : {};
            } catch (e) { scope.weatherReport = {}; }
        }
        onLoadFailed: () => { scope.weatherReport = {}; }
    }
    function weatherLine() {
        const w = scope.weatherReport;
        if (!w || w.temp_c === undefined) return "";
        return "weather: " + w.temp_c + "°C" + (w.summary ? " · " + w.summary : "")
            + " · sensor " + Math.max(0, Math.floor((Date.now() / 1000 - w.observed_at) / 60)) + "m ago";
    }
    function adopt(modeId) {
        adoptProc.command = ["qs", "-c", "quantumfate", "ipc", "call", "--", "focus", "set", modeId, "0"];
        adoptProc.running = true;
    }

    function closePanel() { PanelBus.close("calendar"); }

    // Re-anchor the month view/cursor on today and the region on Upcoming
    // each time the panel reopens, so a stale browse from last time never
    // greets the user.
    property bool _wasOpen: false
    Connections {
        target: PanelBus
        function onOpenChanged() {
            const isOpen = PanelBus.open === "calendar";
            if (isOpen && !scope._wasOpen) {
                scope.viewYear = scope._clock.date.getFullYear();
                scope.viewMonth = scope._clock.date.getMonth();
                scope.cursorDate = scope.todayIso;
                scope.focusRegion = "upcoming";
                scope.upcomingIndex = 0;
                scope.monthExpanded = false;
            }
            scope._wasOpen = isOpen;
        }
    }

    PanelWindow {
        id: win
        visible: PanelBus.open === "calendar"
        screen: PanelBus.screenObject(PanelBus.anchorScreen)
        color: "transparent"

        anchors { top: true; left: true; right: true }
        margins { top: Theme.barReserved + Theme.space.xs }
        implicitHeight: card.implicitHeight

        WlrLayershell.layer: WlrLayer.Overlay
        // Frosted per this namespace in the hypr repo's layerrules.lua —
        // report: namespace "quickshell-calendar", elevation "peek"
        // (alpha Theme.surfaceAlpha.peek = 0.94).
        WlrLayershell.namespace: "quickshell-calendar"
        // OnDemand only while visible: a hidden PanelWindow still exists,
        // and Exclusive/OnDemand on an invisible layer surface can steal
        // focus from whatever's underneath.
        WlrLayershell.keyboardFocus: win.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusiveZone: 0
        mask: Region { item: card }

        Surface {
            id: card
            x: Math.max(Theme.space.sm, Math.min(PanelBus.anchorX - width / 2, parent.width - width - Theme.space.sm))
            y: 0
            width: Math.min(480, parent.width - Theme.space.sm * 2)
            implicitHeight: content.implicitHeight + Theme.space.xl * 2
            elevation: "peek"
            radius: Theme.radius

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: win.visible

                Keys.onEscapePressed: scope.closePanel()
                Keys.onPressed: (event) => {
                    const key = event.text;
                    if (event.key === Qt.Key_Tab && scope.monthExpanded) {
                        scope.focusRegion = scope.focusRegion === "upcoming" ? "month" : "upcoming";
                        event.accepted = true;
                    } else if (key === "m") {
                        scope.monthExpanded = !scope.monthExpanded;
                        scope.focusRegion = scope.monthExpanded ? "month" : "upcoming";
                        event.accepted = true;
                    } else if (scope.focusRegion === "upcoming") {
                        if (key === "j" || event.key === Qt.Key_Down)
                            scope.upcomingIndex = Math.min(scope.upcomingEntries.length - 1, scope.upcomingIndex + 1);
                        else if (key === "k" || event.key === Qt.Key_Up)
                            scope.upcomingIndex = Math.max(0, scope.upcomingIndex - 1);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            // impliedMode is disabled (undesigned
                            // precedence against ModePrecedence.js) and always
                            // returns null — Enter adopts nothing until it does.
                            const ev = scope.upcomingEntries[scope.upcomingIndex];
                            const mode = ev ? CalendarSource.impliedMode(ev, scope.calendarModeDefaults) : null;
                            if (mode) scope.adopt(mode);
                        } else return;
                        event.accepted = true;
                    } else if (scope.focusRegion === "month") {
                        if (key === "h") scope.moveCursor(-1);
                        else if (key === "l") scope.moveCursor(1);
                        else if (key === "j") scope.moveCursor(7);
                        else if (key === "k") scope.moveCursor(-7);
                        else if (key >= "1" && key <= "9") scope.jumpToDay(parseInt(key, 10));
                        else return;
                        event.accepted = true;
                    }
                }

                ColumnLayout {
                    id: content
                    anchors { fill: parent; margins: Theme.space.lg }
                    spacing: Theme.space.md

                    // -- today --------------------------------------------------
                    Text {
                        text: Qt.formatDate(scope._clock.date, "dddd, d MMMM").toLowerCase()
                        color: Theme.accent
                        font { family: Theme.fontFamily; pixelSize: Theme.fs.xl; weight: Font.Bold }
                    }
                    // -- weather (LEO-225): quiet when the local store is
                    // missing; the line names its sensor age, so staleness is
                    // legible rather than assumed fresh.
                    Text {
                        visible: (scope.weatherLine()) !== ""
                        text: scope.weatherLine()
                        color: Theme.subtext
                        font.pixelSize: Theme.fs.xs
                    }

                    Item {
                        id: strip
                        Layout.fillWidth: true
                        implicitHeight: Theme.fs.xl

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusSmall
                            color: Theme.withAlpha(Theme.inset, 0.6)
                            border { width: 1; color: Theme.withAlpha(Theme.border, 0.45) }
                        }

                        // Event blocks, positioned as fractions of the 06:00–24:00
                        // window — no literal pixel geometry here, just the tokens
                        // gate's blind spot: a computed fraction, not a constant.
                        Repeater {
                            model: scope.todayEntries.filter(e => !!e.time)
                            delegate: Rectangle {
                                id: block
                                required property var modelData
                                readonly property real startFrac: Math.max(0, (CalendarSource.timeToMinutes(block.modelData.time) - 360) / (18 * 60))
                                readonly property real durFrac: (block.modelData.durationMinutes || 30) / (18 * 60)
                                x: strip.width * block.startFrac
                                width: Math.max(2, strip.width * block.durFrac)
                                anchors { top: parent.top; bottom: parent.bottom }
                                radius: Theme.radiusSmall
                                color: Theme.withAlpha(Theme.accentSecondary, 0.55)
                                border { width: 1; color: Theme.accentSecondary }
                            }
                        }

                        // `now` marker.
                        Rectangle {
                            visible: CalendarSource.timeToMinutes(scope.nowTime) >= 360
                            x: strip.width * Math.min(1, (CalendarSource.timeToMinutes(scope.nowTime) - 360) / (18 * 60))
                            anchors { top: parent.top; bottom: parent.bottom }
                            implicitWidth: 2
                            color: Theme.pending
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: scope.freeBlocks.length > 0
                            ? scope.freeBlocks.map(g => CalendarSource.durationLabel(g.minutes) + " free").join(" · ")
                            : "no free blocks left today."
                        color: Theme.subtextAlt
                        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                        elide: Text.ElideRight
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                    // -- upcoming -----------------------------------------------
                    Text {
                        text: "upcoming"
                        color: scope.focusRegion === "upcoming" ? Theme.accent : Theme.subtext
                        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: Font.Bold }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.xs

                        Repeater {
                            model: scope.upcomingEntries
                            delegate: Rectangle {
                                id: row
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: label.implicitHeight + Theme.space.xs * 2

                                readonly property bool selected: scope.focusRegion === "upcoming" && row.index === scope.upcomingIndex
                                readonly property string mode: CalendarSource.impliedMode(row.modelData, scope.calendarModeDefaults)

                                radius: Theme.radiusSmall
                                color: row.selected ? Theme.withAlpha(Theme.accent, 0.16) : "transparent"
                                border { width: 1; color: row.selected ? Theme.accent : "transparent" }

                                RowLayout {
                                    id: label
                                    anchors { fill: parent; leftMargin: Theme.space.sm; rightMargin: Theme.space.sm }
                                    spacing: Theme.space.sm

                                    Text {
                                        text: row.modelData.time || "all-day"
                                        color: Theme.subtext
                                        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                                        Layout.preferredWidth: Theme.fs.xl * 2
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: row.modelData.title
                                        color: Theme.text
                                        font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: !!row.modelData.durationMinutes
                                        text: CalendarSource.durationLabel(row.modelData.durationMinutes)
                                        color: Theme.subtextAlt
                                        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                                    }
                                    // impliedMode is disabled and always
                                    // returns null, so `row.mode` is always falsy today —
                                    // hidden rather than deleted so the chip reappears
                                    // the moment the mapping is redesigned and re-enabled.
                                    Rectangle {
                                        visible: !!row.mode
                                        implicitWidth: modeLabel.implicitWidth + Theme.space.sm * 2
                                        implicitHeight: modeLabel.implicitHeight + Theme.space.xs
                                        radius: Theme.radiusSmall
                                        color: Theme.withAlpha(Theme.accentSecondary, 0.22)
                                        border { width: 1; color: Theme.withAlpha(Theme.accentSecondary, 0.6) }
                                        Text {
                                            id: modeLabel
                                            anchors.centerIn: parent
                                            text: row.mode
                                            color: Theme.accentSecondary
                                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: scope.upcomingEntries.length === 0
                            text: PanelBus.calendarLoaded ? "nothing coming up." : "loading…"
                            color: Theme.subtext
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                        }
                    }

                    // -- month (collapsed by default) --------------------------
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: Qt.formatDate(new Date(scope.viewYear, scope.viewMonth, 1), "MMMM yyyy").toLowerCase()
                            color: scope.focusRegion === "month" ? Theme.accent : Theme.subtext
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.sm; weight: Font.Bold }
                        }
                        Text {
                            text: scope.monthExpanded ? "m to collapse" : "m to expand"
                            color: Theme.subtextAlt
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                        }
                    }

                    GridLayout {
                        visible: scope.monthExpanded
                        columns: 7
                        Layout.fillWidth: true
                        rowSpacing: Theme.space.xs
                        columnSpacing: Theme.space.xs

                        Repeater {
                            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                            delegate: Text {
                                required property string modelData
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData
                                color: Theme.overlay
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: Font.Bold }
                            }
                        }

                        Repeater {
                            model: scope.grid
                            delegate: Rectangle {
                                id: cell
                                required property var modelData
                                readonly property bool isToday: cell.modelData.date === scope.todayIso
                                readonly property bool isCursor: cell.modelData.date === scope.cursorDate
                                readonly property int count: scope.counts[cell.modelData.date] || 0
                                Layout.preferredWidth: Theme.fs.xl * 1.4
                                Layout.preferredHeight: Theme.fs.xl * 1.4
                                radius: Theme.radiusSmall
                                color: cell.isToday ? Theme.withAlpha(Theme.accent, 0.32)
                                    : cell.isCursor ? Theme.withAlpha(Theme.accentSecondary, 0.2)
                                    : "transparent"
                                border { width: cell.isCursor && scope.focusRegion === "month" ? 1 : 0; color: Theme.accentSecondary }

                                Text {
                                    anchors.centerIn: parent
                                    // Today never relies on colour alone — bracketing
                                    // the day number keeps it unmistakable under any
                                    // palette, including a colourblind-hostile one.
                                    text: cell.isToday ? "[" + cell.modelData.day + "]" : String(cell.modelData.day)
                                    color: !cell.modelData.inMonth ? Theme.withAlpha(Theme.subtext, 0.4)
                                        : cell.isToday ? Theme.accent : Theme.text
                                    font { family: Theme.fontFamily; pixelSize: Theme.fs.sm; weight: cell.isToday ? Font.Bold : Font.Normal }
                                }
                                Rectangle {
                                    visible: cell.count > 0
                                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Theme.space.xs }
                                    implicitWidth: Theme.space.md; implicitHeight: 2; radius: 1
                                    color: Theme.accentSecondary
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
