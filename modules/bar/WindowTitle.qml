// Active window title for this monitor (waybar hyprland/window, per-output).
import QtQuick
import Quickshell.Hyprland
import "../../services"   // Theme

Text {
    id: root

    // The monitor this bar sits on; only its focused window is shown.
    required property var screen
    readonly property var _monitor: Hyprland.monitorFor(screen)

    color: Theme.c.subtext0
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: 12; rightPadding: 12
    elide: Text.ElideRight
    text: _title()

    // Recompute the title whenever windows or focus change.
    Connections { target: Hyprland.toplevels; function onValuesChanged() { root.text = root._title(); } }
    Connections { target: Hyprland; function onRawEvent(e) { root.text = root._title(); } }

    // Title of the activated window on this monitor, or "" when none.
    function _title() {
        const wins = (Hyprland.toplevels?.values) || [];
        for (const w of wins) {
            if (!w?.activated) continue;
            if (w?.monitor && w.monitor !== root._monitor) continue;
            return (w?.lastIpcObject?.title) ?? w?.title ?? "";
        }
        return "";
    }
}
