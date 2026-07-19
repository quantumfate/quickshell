// Volume (or "Mute"); click toggles mute, scroll adjusts (waybar pulseaudio).
import QtQuick
import "../../services"   // Theme
PollText {
    color: Theme.c.peach
    command: "[ \"$(pamixer --get-mute)\" = true ] && echo 'Mute ' || echo \"$(pamixer --get-volume) \""
    clickCommand: "pamixer -t"
    scrollUpCommand: ",volume.sh --inc"
    scrollDownCommand: ",volume.sh --dec"
    intervalMs: 1000
}
