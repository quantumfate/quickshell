pragma Singleton
// Global paths / constants shared across the whole shell.
// Keep machine-specific mutable state OUT of the git repo -> the shared
// quantum-store directory ($QF_STORE, default $XDG_STATE_HOME/quantum-store).
import Quickshell
import QtQuick

Singleton {
    id: root

    // Legacy location for a store the desk has not migrated yet: this is only
    // ever a read-back, never a write target.
    readonly property string legacyStateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))

    // Root for shared Store state files ($QF_STORE/<name>.json), shared with
    // the Hyprland Lua config, the shell helpers and the nvim stores. The
    // store directory is where the desktop keeps state, not the bare state
    // home — one dir so relocating the whole collection is a move, not a find.
    // UWSM does not always carry the compositor's exported QF_STORE into the
    // graphical shell. The default must still be the shared quantum-store,
    // never the pre-store legacy root, or Lua writes become invisible to QML.
    readonly property string stateDir: Quickshell.env("QF_STORE") || (legacyStateDir + "/quantum-store")
}
