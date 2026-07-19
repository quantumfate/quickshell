// WorkspaceTaskbar — the default taskbar: every window on this bar monitor's
// active workspace, as a WindowStrip. Follows workspace switches. Normal windows
// get focus / rename / close (no reorder or Dofus capture). This is the generic
// counterpart to DofusTaskbar, both built on WindowStrip.
import QtQuick
import Quickshell.Hyprland
import "../../services"   // Hypr

WindowStrip {
    id: taskbar

    // The monitor whose active workspace we mirror.
    required property var screen
    screenName: screen.name

    // Plain default taskbar: no focused-window highlight.
    highlightActive: false

    // Bumped on any compositor change so `slots` recomputes from live state.
    property int _tick: 0
    Connections { target: Hyprland.toplevels; function onValuesChanged() { taskbar._tick++; } }
    Connections { target: Hyprland; function onRawEvent(e) { taskbar._tick++; } }

    slots: {
        _tick;   // dependency: force recompute on compositor changes
        return taskbar._windowsOnActiveWorkspace();
    }

    onFocus: (s) => Hypr.focus(s.selector)
    onRename: (s, text) => Hypr.retitle(s.pid, text)
    onClose: (s) => Hypr.close(s.selector)

    // Live windows on this monitor's active workspace, as strip slots. Address
    // is the stable selector when present; title otherwise (matches Hypr.focus).
    function _windowsOnActiveWorkspace() {
        const wsId = Hyprland.monitorFor(screen)?.activeWorkspace?.id;
        const out = [];
        for (const w of (Hyprland.toplevels?.values || [])) {
            const ipc = w?.lastIpcObject;
            const wid = ipc?.workspace?.id;
            if (wsId !== undefined && wid !== undefined && wid !== wsId) continue;
            const title = (ipc?.title) ?? w?.title ?? "(untitled)";
            out.push({
                name: title,
                present: true,
                focused: !!w?.activated,
                selector: ipc?.address ? "address:" + ipc.address : "title:" + title,
                pid: ipc?.pid ?? -1,
                title: title
            });
        }
        return out;
    }
}
