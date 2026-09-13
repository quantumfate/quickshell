// GroupChip — left zone, only when the focused window sits in a Hyprland
// group (04-persistent-bar.md). A grouped window's own groupbar already
// names every member and marks the focused one, so this chip only needs
// "name · i/n" — the group's identity, not its membership list.
import QtQuick
import "../../services"   // Theme

PollText {
    color: Theme.accent
    font.weight: Font.Bold
    // Empty stdout (ungrouped focus) hides the chip entirely — no placeholder.
    visible: text !== ""
    command: "hyprctl -j activewindow | jq -r '" +
        "if (.grouped // []) == [] then \"\" else " +
        "(.grouped | length) as $n | " +
        "(.grouped | index(.address // \"\")) as $i | " +
        "(.initialTitle // .class // \"group\") + \" · \" + " +
        "((($i // 0) + 1) | tostring) + \"/\" + ($n | tostring) end'"
    intervalMs: 500
}
