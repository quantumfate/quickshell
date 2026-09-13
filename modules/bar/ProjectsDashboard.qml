// ProjectsDashboard — the fuller view behind ProjectsPill: per repo, branch,
// dirty count, ahead/behind, last-commit age. Driven by PanelBus.open so the
// pill (on whichever screen) and this single panel stay in sync, same as
// services/SysMon.qml drives SysPanel.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme
import "../common"        // Surface
import "ProjectsHealth.js" as ProjectsHealth

Scope {
    id: scope

    PanelWindow {
        visible: PanelBus.open === "projects"
        screen: Quickshell.screens.find(s => s.name === PanelBus.anchorScreen) ?? null
        color: "transparent"

        anchors { top: true; left: true; right: true }
        margins { top: Theme.barReserved + Theme.space.xs }
        implicitHeight: card.implicitHeight

        WlrLayershell.layer: WlrLayer.Overlay
        // Frosted per this namespace in the hypr repo's layerrules.lua —
        // report: namespace "quickshell-projects-dashboard", elevation "peek"
        // (alpha Theme.surfaceAlpha.peek = 0.85).
        WlrLayershell.namespace: "quickshell-projects-dashboard"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusiveZone: 0
        mask: Region { item: card }

        Surface {
            id: card
            x: Math.max(Theme.space.sm, Math.min(PanelBus.anchorX - width / 2, parent.width - width - Theme.space.sm))
            y: 0
            width: Math.min(420, parent.width - Theme.space.sm * 2)
            implicitHeight: content.implicitHeight + Theme.space.xl * 2
            elevation: "peek"
            radius: Theme.radiusPill

            ColumnLayout {
                id: content
                anchors { fill: parent; margins: Theme.space.lg }
                spacing: Theme.space.sm

                Text {
                    text: "Projects"
                    color: Theme.accent
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.lg; weight: Font.Bold }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                Repeater {
                    model: ProjectsHealth.sortedRows(PanelBus.projectRepos)
                    delegate: RowLayout {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Theme.space.sm

                        readonly property string role: ProjectsHealth.roleFor(row.modelData.state)
                        readonly property color tint: role === "error" ? Theme.error
                            : role === "warn" ? Theme.warning
                            : role === "neutral" ? Theme.overlay
                            : Theme.success

                        Rectangle {
                            implicitWidth: 8; implicitHeight: 8; radius: 4
                            color: row.tint
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: row.modelData.name
                            color: Theme.text
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.sm; weight: Font.DemiBold }
                            Layout.preferredWidth: 110
                            elide: Text.ElideRight
                        }
                        Text {
                            text: row.modelData.branch || row.modelData.state
                            color: Theme.subtext
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: row.role === "ok" || row.role === "neutral"
                            text: (row.modelData.dirty ? "●" + row.modelData.dirty + " " : "")
                                + (row.modelData.ahead ? "↑" + row.modelData.ahead + " " : "")
                                + (row.modelData.behind ? "↓" + row.modelData.behind + " " : "")
                                + ProjectsHealth.fmtAge(ProjectsHealth.ageOf(row.modelData))
                            color: Theme.subtext
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                        }
                    }
                }

                Text {
                    visible: Object.keys(PanelBus.projectRepos).length === 0
                    text: PanelBus.projectHealthLoaded
                        ? "No project health data yet (projects-health.json not found)."
                        : "Loading…"
                    color: Theme.subtext
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                }
            }
        }
    }
}
