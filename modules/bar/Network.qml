// Active connection name (wifi essid or "Disconnected"); right-click opens the
// NetworkManager editor (waybar network).
import QtQuick
import "../../services"   // Theme
PollText {
    color: Theme.c.sky
    command: "nmcli -t -f NAME connection show --active 2>/dev/null | head -1 | grep . || echo Disconnected"
    clickCommand: "nm-connection-editor"
    intervalMs: 5000
}
