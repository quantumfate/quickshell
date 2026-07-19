// Backlight level with icon; scroll to adjust (waybar custom/brightness).
import QtQuick
import "../../services"   // Theme
PollText {
    color: Theme.c.yellow
    command: ",brightness.sh --get-with-icon"
    scrollUpCommand: ",brightness.sh --inc"
    scrollDownCommand: ",brightness.sh --dec"
    intervalMs: 1000
}
