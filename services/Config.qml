pragma Singleton
// Global paths / constants shared across the whole shell.
// Keep machine-specific mutable state OUT of the git repo -> XDG_STATE_HOME.
import Quickshell
import QtQuick

Singleton {
    id: root

    // Root for shared Store state files ($XDG_STATE_HOME/<name>.json), shared
    // with the Hyprland Lua config. Mutable state -> ~/.local/state, not the repo.
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
}
