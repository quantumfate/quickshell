// Volume of the default audio sink — event-driven via Pipewire (no polling).
// Click toggles mute, scroll adjusts in 5% steps. Filename kept for the bar's
// import; the backend is Pipewire, not pamixer. Bar centre control
// (04-persistent-bar.md): glyph + track, matching Brightness.
import QtQuick
import Quickshell.Services.Pipewire

MeterControl {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink?.audio ?? null

    // Pipewire only streams a node's audio props while it's tracked; without
    // this, volume/muted never update.
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    glyph: ""
    muted: !!audio?.muted
    ratio: audio?.volume ?? 0
    valueText: !audio ? "" : audio.muted ? "muted" : Math.round(audio.volume * 100) + "%"
    tip: root.sink
        ? (root.sink.description || root.sink.name || "Audio")
          + (root.audio?.muted ? " · muted" : " · " + Math.round((root.audio?.volume ?? 0) * 100) + "%")
        : "No audio sink"

    function _setVol(v) { if (audio) audio.volume = Math.max(0, Math.min(1, v)); }

    onTapped: if (root.audio) root.audio.muted = !root.audio.muted
    onWheelUp: root._setVol((root.audio?.volume ?? 0) + 0.05)
    onWheelDown: root._setVol((root.audio?.volume ?? 0) - 0.05)
}
