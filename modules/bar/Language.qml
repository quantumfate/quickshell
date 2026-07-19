// Keyboard layout indicator; click cycles the layout (waybar custom/language).
import QtQuick
import "../../services"   // Theme
PollText {
    color: Theme.c.overlay1
    command: "$HOME/.config/waybar/scripts/language.sh"
    clickCommand: "hyprctl switchxkblayout all next"
    intervalMs: 2000
}
