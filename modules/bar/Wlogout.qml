// Power/logout entry point; click opens the wlogout menu (waybar custom/wlogout).
import QtQuick
import "../../services"   // Theme
PollText {
    color: logoutHover.hovered ? Theme.c.maroon : Theme.c.red
    HoverHandler { id: logoutHover }
    command: "echo ' 󰣇 '"   // static nerd-font arch glyph
    clickCommand: "uwsm app -- $HOME/.config/waybar/scripts/wlogout.sh"
    intervalMs: 3600000
}
