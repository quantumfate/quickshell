pragma Singleton
// BarInput — shared flag for "a bar text field is being edited right now"
// (currently the inline taskbar-chip rename). The bar binds its layer-shell
// keyboard focus to this: None normally (so clicking the bar never steals focus
// from the focused app/game), Exclusive while editing so keystrokes reach the
// TextInput. `screen` scopes the grab to the ONE bar being edited — two layer
// surfaces both requesting exclusive keyboard focus is a compositor hazard.
import Quickshell
import QtQuick

Singleton {
    id: root
    property bool renaming: false
    property string screen: ""      // name of the screen whose bar is editing
    function begin(screenName) { root.screen = screenName || ""; root.renaming = true; }
    function end() { root.renaming = false; root.screen = ""; }
}
