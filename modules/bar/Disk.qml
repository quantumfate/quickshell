// Free space on the root filesystem (waybar disk, format "{free}").
import QtQuick
import "../../services"   // Theme
PollText {
    color: Theme.c.sapphire
    command: "df -h --output=avail / | tail -1 | tr -d ' '"
    intervalMs: 30000
}
