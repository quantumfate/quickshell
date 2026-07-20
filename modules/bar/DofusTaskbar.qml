// Dofus taskbar: the team's live windows as a WindowStrip, in team.json order,
// with the full Dofus action set (focus, rename→state, reorder→state, close,
// and ◎ capture-turn-hash). Only characters with an open window get a chip.
import QtQuick
import "../../services"   // DofusWindows, DofusState, DofusSwap

WindowStrip {
    // The workspace this strip mirrors (its monitor's active workspace). Only
    // Dofus windows on it show — same current-workspace rule as the default bar.
    required property int activeWs

    // Present team windows + any unmatched Dofus windows on this workspace.
    slots: DofusWindows.taskbarOn(activeWs)

    onFocus: (s) => DofusWindows.focus(s.selector)
    onRename: (s, text) => DofusWindows.rename(s.index, s.pid, text)
    onReorder: (s, dir) => DofusState.reorder(s.index, s.index + dir)
    onClose: (s) => DofusWindows.close(s.selector)
    onCapture: (s) => DofusSwap.learn(s.name)
}
