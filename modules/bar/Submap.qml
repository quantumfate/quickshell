// Current Hyprland submap name, or empty in the default map (waybar submap).
// Tracked from the `submap` raw event, which carries the new map name as data.
import QtQuick
import Quickshell.Hyprland
import "../../services"   // Theme

Text {
    id: root
    color: Theme.c.mauve
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Font.Bold }
    leftPadding: 10; rightPadding: 10
    text: ""
    visible: text !== ""

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") root.text = (event.data || "").trim();
        }
    }
}
