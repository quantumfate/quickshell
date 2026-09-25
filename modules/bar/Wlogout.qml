// Power/logout entry point; click opens the power menu.
//
// Through hypr's `,logout.sh`, which owns the menu's arguments (its layout,
// and the stylesheet the active palette renders) and toggles it, rather than
// spawning wlogout directly. This used to call a waybar-era script that no
// longer exists, so the button silently did nothing.
import QtQuick
import "../../services"   // Theme
PollText {
    color: logoutHover.hovered ? Theme.c.maroon : Theme.c.red
    HoverHandler { id: logoutHover }
    command: "echo ' 󰣇 '"   // static nerd-font arch glyph
    clickCommand: "uwsm app -- ,logout.sh"
    intervalMs: 3600000
}
