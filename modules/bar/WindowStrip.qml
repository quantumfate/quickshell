// WindowStrip — a taskbar strip over an arbitrary window set. The caller passes
// `slots` (already resolved + ordered) and wires whichever action handlers apply
// to this class of window; a button appears only when its handler is set. This
// is the abstraction behind both the Dofus taskbar and the workspace taskbar.
//
// Handler signatures (any may be left null to hide that action):
//   onFocus(slot)              focus + raise
//   onRename(slot, text)       commit a new name/title
//   onReorder(slot, dir)       dir = -1 left / +1 right
//   onClose(slot)              close the window
//   onCapture(slot)            Dofus-only: learn this turn's hash
import QtQuick
import "../../services"

Row {
    id: strip
    spacing: 4

    // Resolved, ordered windows: [{ name, present, focused, selector, pid }, …].
    property var slots: []

    // Screen this strip is on — forwarded so chip tooltips reach the right layer.
    property string screenName: ""

    // Highlight the focused window; off for the plain default taskbar.
    property bool highlightActive: true

    property var onFocus: null
    property var onRename: null
    property var onReorder: null
    property var onClose: null
    property var onCapture: null

    Repeater {
        model: strip.slots
        delegate: WindowChip {
            required property var modelData
            required property int index
            slot: modelData
            screenName: strip.screenName
            highlightActive: strip.highlightActive

            showRename: !!strip.onRename
            showReorder: !!strip.onReorder
            showClose: !!strip.onClose
            showCapture: !!strip.onCapture
            canLeft: index > 0
            canRight: index < strip.slots.length - 1

            onFocusRequested: if (strip.onFocus) strip.onFocus(modelData)
            onRenameRequested: (text) => { if (strip.onRename) strip.onRename(modelData, text); }
            onReorderRequested: (dir) => { if (strip.onReorder) strip.onReorder(modelData, dir); }
            onCloseRequested: if (strip.onClose) strip.onClose(modelData)
            onCaptureRequested: if (strip.onCapture) strip.onCapture(modelData)
        }
    }
}
