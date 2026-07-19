// Notification (mako) status; click toggles do-not-disturb (waybar custom/mako).
import QtQuick
import "../../services"   // Theme
PollText {
    color: Theme.c.overlay1
    command: ",mako.sh"
    clickCommand: "makoctl mode -t do-not-disturb"
    intervalMs: 1000
}
