// Dofus taskbar: the team's live windows as a WindowStrip, in team.json order,
// with the full Dofus action set (focus, rename→state, reorder→state, close,
// and ◎ capture-turn-hash). Only characters with an open window get a chip.
import QtQuick
import "../../services"   // DofusWindows, DofusState, DofusSwap

WindowStrip {
    slots: DofusWindows.slots.filter(s => s.present)

    onFocus: (s) => DofusWindows.focus(s.title)
    onRename: (s, text) => DofusWindows.rename(s.index, s.pid, text)
    onReorder: (s, dir) => DofusState.reorder(s.index, s.index + dir)
    onClose: (s) => DofusWindows.close(s.title)
    onCapture: (s) => DofusSwap.learn(s.name)
}
