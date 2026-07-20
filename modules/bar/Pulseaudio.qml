// Volume of the default audio sink — event-driven via Pipewire (no polling).
// Click toggles mute, scroll adjusts in 5% steps. Shows "Mute" when muted.
// (Filename kept for the bar's import; the backend is now Pipewire, not pamixer.)
import QtQuick
import Quickshell.Services.Pipewire
import "../../services"   // Theme, Tip

Text {
    id: root

    property string screenName: ""

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink?.audio ?? null

    // Pipewire only streams a node's audio props while it's tracked; without
    // this, volume/muted never update.
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    color: Theme.c.peach
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: 10; rightPadding: 10
    text: !audio ? "-- " : audio.muted ? "Mute " : Math.round(audio.volume * 100) + " "

    // Clamp a proposed 0..1 volume and apply it to the sink.
    function _setVol(v) {
        if (audio) audio.volume = Math.max(0, Math.min(1, v));
    }

    MouseArea {
        anchors.fill: parent
        onClicked: if (root.audio) root.audio.muted = !root.audio.muted
        onWheel: (w) => root._setVol(root.audio.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05))
    }

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: root.sink
            ? (root.sink.description || root.sink.name || "Audio")
              + (root.audio?.muted ? " · muted" : " · " + Math.round((root.audio?.volume ?? 0) * 100) + "%")
            : "No audio sink"
    }
}
