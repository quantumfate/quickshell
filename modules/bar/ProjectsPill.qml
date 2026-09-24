// ProjectsPill — bar glance at project health (projects-health.json, produced
// outside this repo by whatever runs the repo scan; read once by PanelBus and
// shared with ProjectsDashboard). Click opens the dashboard for the per-repo
// breakdown. Degrades quietly when the health file doesn't exist yet on this
// machine: shows nothing alarming, no error.
import QtQuick
import "../../services"   // Theme
import "ProjectsHealth.js" as ProjectsHealth

Text {
    id: root
    property string screenName: ""

    readonly property var summary: ProjectsHealth.summarize(PanelBus.projectRepos)
    readonly property color tint: summary.worstRole === "error" ? Theme.error
        : summary.worstRole === "warn" ? Theme.warning
        : Theme.c.green

    visible: PanelBus.projectHealthLoaded && summary.total > 0
    color: hover.hovered ? Theme.text : root.tint
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: Theme.space.md; rightPadding: Theme.space.md
    text: "" + summary.total + (summary.dirtyTotal > 0 ? " ●" + summary.dirtyTotal : "")

    MouseArea {
        anchors.fill: parent
        onClicked: PanelBus.toggle("projects", root.screenName, root.mapToItem(null, root.width / 2, 0).x, "bar.workspaces")
    }

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: root.summary.total + " repos · " + root.summary.byState.ok + " ok"
            + (root.summary.byState.error ? " · " + root.summary.byState.error + " error" : "")
            + (root.summary.byState.timeout + root.summary.byState.missing > 0
                ? " · " + (root.summary.byState.timeout + root.summary.byState.missing) + " unreachable" : "")
            + " · click for details"
    }
}
