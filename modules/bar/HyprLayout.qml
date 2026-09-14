// Active workspace's tiling layout name (waybar custom/hyprlayout).
import QtQuick
import "../../services"   // Theme
PollText {
    // Custom Lua layouts report their registered name with the compositor's
    // "lua:" prefix (e.g. "lua:scene"); spell the readable half.
    command: "hyprctl -j activeworkspace | jq -r '.tiledLayout | sub(\"^lua:\"; \"\")'"
    intervalMs: 1000
}
