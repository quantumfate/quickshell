// SysMonitor — the compact CPU · RAM · disk · network cluster in the bar,
// replacing the four standalone widgets. Reads SysStats. Hovering peeks the
// detail panel (SysPanel); clicking pins it open. The keybind/IPC toggle
// (sysmon) pins it too.
import QtQuick
import QtQuick.Layouts
import "../../services"   // SysStats, SysMon, Theme

RowLayout {
    id: root
    required property string screenName
    spacing: 10

    // A glyph + value pair. Colored per stat; the whole cluster shares hover.
    component Stat: RowLayout {
        property string glyph: ""
        property string value: ""
        property color tint: Theme.text
        spacing: 4
        Text {
            text: parent.glyph; color: parent.tint
            font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
        }
        Text {
            text: parent.value; color: Theme.text
            font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
        }
    }

    Stat { glyph: "󰻠"; tint: Theme.c.lavender; value: SysStats.cpuPct + "%" }
    Stat { glyph: "󰍛"; tint: Theme.c.blue; value: SysStats.memUsedG.toFixed(1) + "G" }
    Stat { glyph: "󰋊"; tint: Theme.c.sapphire; value: SysStats.diskFree }
    Stat {
        glyph: SysStats.wifiSignal >= 0 ? "󰖩" : "󰈀"
        tint: Theme.c.sky
        value: "󰇚" + SysStats.fmtRate(SysStats.rxRate).replace("/s", "")
    }

    // Whole-cluster hover → peek; click → pin. Anchor x is the cluster centre.
    HoverHandler { id: hover }
    TapHandler {
        onTapped: SysMon.togglePin(root.screenName, root._centerX())
    }
    function _centerX() { return root.mapToItem(null, root.width / 2, 0).x; }

    Connections {
        target: hover
        function onHoveredChanged() {
            if (hover.hovered) SysMon.peek(root.screenName, root._centerX());
            else SysMon.unpeek(root.screenName);
        }
    }
}
