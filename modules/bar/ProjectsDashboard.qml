// ProjectsDashboard — the fuller view behind ProjectsPill: per repo, branch,
// dirty count, ahead/behind, last-commit age. Driven by PanelBus.open so the
// pill (on whichever screen) and this single panel stay in sync, same as
// services/SysMon.qml drives SysPanel.
//
// Card width is sized to content (widest repo name/branch line), not a fixed
// pixel budget — a narrow fixed column is what used to elide repo names.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, Config
import "../common"        // Surface
import "ProjectsHealth.js" as ProjectsHealth

Scope {
    id: scope

    // collected_at, read directly rather than threaded through PanelBus: the
    // pill only ever needed the repo map, so that's all PanelBus exposes.
    // Staleness must be shown, not hidden, so this panel needs the timestamp
    // too — read the same file a second time rather than widen PanelBus for
    // one field only this panel cares about.
    FileView {
        id: healthFile
        path: Config.stateDir + "/projects-health.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                scope.collectedAt = (JSON.parse(text() || "{}")).collected_at ?? "";
            } catch (e) {
                scope.collectedAt = "";
            }
        }
        onLoadFailed: scope.collectedAt = ""
    }
    property string collectedAt: ""

    PanelWindow {
        visible: PanelBus.open === "projects"
        screen: PanelBus.screenObject(PanelBus.anchorScreen)
        color: "transparent"

        anchors { top: true; left: true; right: true }
        margins { top: Theme.barReserved + Theme.space.md }
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
            width: Math.min(content.implicitWidth + Theme.space.xl * 2, parent.width - Theme.space.sm * 2)
            implicitHeight: content.implicitHeight + Theme.space.xl * 2
            elevation: "peek"
            radius: Theme.radiusPill

            ColumnLayout {
                id: content
                anchors { fill: parent; margins: Theme.space.lg }
                spacing: Theme.space.sm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.sm

                    Text {
                        text: "projects"
                        color: Theme.accent
                        font { family: Theme.fontFamily; pixelSize: Theme.fs.lg; weight: Font.Bold }
                    }
                    Item { Layout.fillWidth: true }
                    // Shown even when fresh: a silently-stale timer failure is
                    // exactly the kind of thing this panel exists to surface.
                    Text {
                        readonly property var staleSec: ProjectsHealth.collectionAge(scope.collectedAt)
                        readonly property bool stale: staleSec !== null && staleSec > 1800
                        visible: scope.collectedAt !== ""
                        text: "updated " + ProjectsHealth.fmtAge(staleSec) + (stale ? " ago · stale" : " ago")
                        color: stale ? Theme.pending : Theme.subtextAlt
                        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                Repeater {
                    model: ProjectsHealth.sortedRows(PanelBus.projectRepos)
                    delegate: ColumnLayout {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Theme.space.xs

                        readonly property string role: ProjectsHealth.roleFor(row.modelData.state)
                        // "ok" reads as accentSecondary (a clean tree is
                        // notable, not just a pass/fail green), "warn" states
                        // (timeout/missing) as pending — not yet a failure,
                        // just unreachable this run.
                        readonly property color tint: role === "error" ? Theme.error
                            : role === "warn" ? Theme.pending
                            : role === "neutral" ? Theme.subtextAlt
                            : Theme.accentSecondary

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.sm

                            Rectangle {
                                implicitWidth: Theme.space.sm; implicitHeight: Theme.space.sm
                                radius: Theme.radiusSmall
                                color: row.tint
                                Layout.alignment: Qt.AlignVCenter
                            }
                            // Full name, never elided — a narrow fixed column
                            // here is exactly what used to truncate repo
                            // names ("us-scrip…", "ce.nvim").
                            Text {
                                text: row.modelData.name
                                color: Theme.text
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.sm; weight: Font.DemiBold }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: row.modelData.branch || row.modelData.state
                                color: Theme.subtext
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.space.sm + Theme.space.sm // clear the dot above
                            spacing: Theme.space.sm
                            visible: row.role === "ok" || row.role === "neutral"

                            Text {
                                text: (row.modelData.dirty ? row.modelData.dirty + " dirty · " : "")
                                    + (row.modelData.ahead ? row.modelData.ahead + " ahead · " : "")
                                    + (row.modelData.behind ? row.modelData.behind + " behind · " : "")
                                    + ProjectsHealth.fmtAge(ProjectsHealth.ageOf(row.modelData))
                                color: Theme.subtextAlt
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                            }
                        }
                    }
                }

                Text {
                    visible: Object.keys(PanelBus.projectRepos).length === 0
                    text: PanelBus.projectHealthLoaded
                        ? "no project health data yet (projects-health.json not found)"
                        : "loading…"
                    color: Theme.subtext
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                // Legend — every symbol used above, explained once.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.md

                    RowLayout {
                        spacing: Theme.space.xs
                        Rectangle { implicitWidth: Theme.space.sm; implicitHeight: Theme.space.sm; radius: Theme.radiusSmall; color: Theme.accentSecondary }
                        Text { text: "ok"; color: Theme.subtextAlt; font { family: Theme.fontFamily; pixelSize: Theme.fs.xs } }
                    }
                    RowLayout {
                        spacing: Theme.space.xs
                        Rectangle { implicitWidth: Theme.space.sm; implicitHeight: Theme.space.sm; radius: Theme.radiusSmall; color: Theme.subtextAlt }
                        Text { text: "plain"; color: Theme.subtextAlt; font { family: Theme.fontFamily; pixelSize: Theme.fs.xs } }
                    }
                    RowLayout {
                        spacing: Theme.space.xs
                        Rectangle { implicitWidth: Theme.space.sm; implicitHeight: Theme.space.sm; radius: Theme.radiusSmall; color: Theme.pending }
                        Text { text: "unreachable"; color: Theme.subtextAlt; font { family: Theme.fontFamily; pixelSize: Theme.fs.xs } }
                    }
                    RowLayout {
                        spacing: Theme.space.xs
                        Rectangle { implicitWidth: Theme.space.sm; implicitHeight: Theme.space.sm; radius: Theme.radiusSmall; color: Theme.error }
                        Text { text: "error"; color: Theme.subtextAlt; font { family: Theme.fontFamily; pixelSize: Theme.fs.xs } }
                    }
                }
            }
        }
    }
}
