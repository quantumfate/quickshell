// Active workspace's tiling layout name (waybar custom/hyprlayout).
import QtQuick
import "../../services"   // Theme
PollText {
    color: Theme.c.overlay1
    command: "hyprctl -j activeworkspace | jq -r '.tiledLayout'"
    intervalMs: 1000
}
