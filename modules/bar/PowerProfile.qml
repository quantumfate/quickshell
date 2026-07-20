// PowerProfile — the active power-profiles-daemon profile as an icon; click
// cycles power-saver → balanced → performance. Event-driven off PowerProfiles;
// hidden when the daemon exposes no performance profile (e.g. no PPD).
import QtQuick
import Quickshell.Services.UPower
import "../../services"   // Theme, Tip

Text {
    id: root

    property string screenName: ""

    // Show only where switching is meaningful (PPD present with a perf profile).
    visible: PowerProfiles.hasPerformanceProfile

    readonly property int profile: PowerProfiles.profile
    color: profile === PowerProfile.Performance ? Theme.c.red
         : profile === PowerProfile.PowerSaver ? Theme.c.green
         : Theme.c.sapphire
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: 10; rightPadding: 10

    text: (profile === PowerProfile.Performance ? "󰓅"
         : profile === PowerProfile.PowerSaver ? "󰌪"
         : "󰾅") + " "

    function _name(p) {
        return p === PowerProfile.Performance ? "Performance"
             : p === PowerProfile.PowerSaver ? "Power saver" : "Balanced";
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        // Cycle saver → balanced → performance, skipping perf if unsupported.
        onClicked: {
            const p = root.profile;
            PowerProfiles.profile = p === PowerProfile.PowerSaver ? PowerProfile.Balanced
                : p === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile
                    ? PowerProfile.Performance
                : PowerProfile.PowerSaver;
        }
    }

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: root._name(root.profile) + " · click to cycle"
    }
}
