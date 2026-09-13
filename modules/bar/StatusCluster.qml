// StatusCluster — the bar's single "system status" entry. Replaces six
// always-on modules (SysMonitor, Weather, Brightness, PowerProfile,
// IdleInhibit, Language) that each answered a question asked occasionally,
// not continuously. Shows one glance value (CPU load); hover peeks the full
// breakdown and quick controls in SysPanel, click pins it open.
import QtQuick
import QtQuick.Layouts
import "../../services"   // SysStats, SysMon, Theme

RowLayout {
    id: root
    required property string screenName
    spacing: Theme.space.sm

    Text {
        text: "󰻠"
        color: Theme.c.lavender
        font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    }
    Text {
        text: SysStats.cpuPct + "%"
        color: Theme.text
        font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    }

    // Whole-cluster hover → peek; click → pin. Anchor x is the cluster centre.
    HoverHandler { id: hover }
    TapHandler { onTapped: SysMon.togglePin(root.screenName, root._centerX()) }
    function _centerX() { return root.mapToItem(null, root.width / 2, 0).x; }

    Connections {
        target: hover
        function onHoveredChanged() {
            if (hover.hovered) SysMon.peek(root.screenName, root._centerX());
            else SysMon.unpeek(root.screenName);
        }
    }
}
