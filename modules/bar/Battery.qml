// Battery — charge %, charge state icon, and time-to-full/empty tooltip, driven
// entirely by UPower events (no polling). Hidden on desktops: it only shows when
// the display device is a real laptop battery that's present.
import QtQuick
import Quickshell.Services.UPower
import "../../services"   // Theme, Tip

Text {
    id: root

    // Optional: screen this widget lives on, so its tooltip reaches the right
    // TipLayer. Left empty on monitors that don't need routed tips.
    property string screenName: ""

    readonly property var dev: UPower.displayDevice
    // Only laptop batteries that are actually present are worth a bar slot.
    visible: dev && dev.isLaptopBattery && dev.isPresent

    readonly property int pct: Math.round((dev?.percentage ?? 0) * 100)
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging
                                  || dev?.state === UPowerDeviceState.FullyCharged
    // Low battery goes red, charging goes green, otherwise the theme's yellow.
    color: charging ? Theme.c.green : pct <= 15 ? Theme.c.red : Theme.c.yellow
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: 10; rightPadding: 10

    // A nerd-font battery glyph in ~10% steps, plus a charging bolt.
    readonly property var _glyphs: ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    text: (charging ? "󰂄 " : _glyphs[Math.min(10, Math.round(pct / 10))] + " ") + pct + "% "

    // Human "1h 23m" from a second count; "" when the estimate isn't ready.
    function _hm(secs) {
        if (!(secs > 0)) return "";
        const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60);
        return (h > 0 ? h + "h " : "") + m + "m";
    }

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: {
            const dev = root.dev;
            if (!dev) return "";
            if (root.charging) {
                const t = root._hm(dev.timeToFull);
                return dev.state === UPowerDeviceState.FullyCharged
                    ? "Fully charged" : "Charging" + (t ? " · " + t + " to full" : "");
            }
            const t = root._hm(dev.timeToEmpty);
            return "On battery" + (t ? " · " + t + " remaining" : "");
        }
    }
}
