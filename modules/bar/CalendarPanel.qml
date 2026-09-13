// CalendarPanel — month grid + today's entries, opened from CalendarPill.
// Same PanelBus-driven single-window pattern as ProjectsDashboard.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme
import "../common"        // Surface
import "CalendarSource.js" as CalendarSource

Scope {
    id: scope

    readonly property var _clock: SystemClock { precision: SystemClock.Minute }
    readonly property string todayIso: Qt.formatDate(scope._clock.date, "yyyy-MM-dd")
    readonly property int viewYear: scope._clock.date.getFullYear()
    readonly property int viewMonth: scope._clock.date.getMonth()

    readonly property var grid: CalendarSource.monthGrid(scope.viewYear, scope.viewMonth)
    readonly property var counts: CalendarSource.countsByDate(PanelBus.calendarEntries)
    readonly property var todayEntries: CalendarSource.entriesOn(PanelBus.calendarEntries, scope.todayIso)

    PanelWindow {
        visible: PanelBus.open === "calendar"
        screen: Quickshell.screens.find(s => s.name === PanelBus.anchorScreen) ?? null
        color: "transparent"

        anchors { top: true; left: true; right: true }
        margins { top: Theme.barReserved + Theme.space.xs }
        implicitHeight: card.implicitHeight

        WlrLayershell.layer: WlrLayer.Overlay
        // Frosted per this namespace in the hypr repo's layerrules.lua —
        // report: namespace "quickshell-calendar", elevation "peek"
        // (alpha Theme.surfaceAlpha.peek = 0.85).
        WlrLayershell.namespace: "quickshell-calendar"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusiveZone: 0
        mask: Region { item: card }

        Surface {
            id: card
            x: Math.max(Theme.space.sm, Math.min(PanelBus.anchorX - width / 2, parent.width - width - Theme.space.sm))
            y: 0
            width: Math.min(320, parent.width - Theme.space.sm * 2)
            implicitHeight: content.implicitHeight + Theme.space.xl * 2
            elevation: "peek"
            radius: Theme.radiusPill

            ColumnLayout {
                id: content
                anchors { fill: parent; margins: Theme.space.lg }
                spacing: Theme.space.sm

                Text {
                    text: Qt.formatDate(scope._clock.date, "MMMM yyyy")
                    color: Theme.accent
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.lg; weight: Font.Bold }
                }

                GridLayout {
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
                            readonly property int count: scope.counts[cell.modelData.date] || 0
                            Layout.preferredWidth: Theme.fs.xl * 1.4
                            Layout.preferredHeight: Theme.fs.xl * 1.4
                            radius: Theme.radiusSmall
                            color: cell.isToday ? Theme.withAlpha(Theme.accent, 0.28) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: cell.modelData.day
                                color: !cell.modelData.inMonth ? Theme.withAlpha(Theme.subtext, 0.4)
                                    : cell.isToday ? Theme.accent : Theme.text
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                            }
                            Rectangle {
                                visible: cell.count > 0
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Theme.space.xs }
                                implicitWidth: 4; implicitHeight: 4; radius: 2
                                color: Theme.c.pink
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                Text {
                    text: "Today"
                    color: Theme.subtext
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: Font.Bold }
                }
                Repeater {
                    model: scope.todayEntries
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Theme.space.sm
                        Text {
                            visible: !!parent.modelData.time
                            text: parent.modelData.time
                            color: Theme.overlay
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: parent.modelData.title
                            color: Theme.text
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                            elide: Text.ElideRight
                        }
                    }
                }
                Text {
                    visible: scope.todayEntries.length === 0
                    text: "Nothing scheduled."
                    color: Theme.subtext
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                }
            }
        }
    }
}
