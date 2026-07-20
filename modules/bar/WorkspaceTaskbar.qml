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
    //
    // STRICT inclusion: a window shows only when its workspace is definitively
    // known, non-special (>= 0), and equal to a known current workspace. Anything
    // uncertain (undefined workspace, no current workspace) is excluded, not
    // leaked onto every taskbar. `workspace.id` (Quickshell-tracked) is preferred
    // over lastIpcObject, which can lag or read undefined mid-transition.
    function _windowsOnActiveWorkspace() {
        const wsId = Hyprland.monitorFor(screen)?.activeWorkspace?.id;
        if (wsId === undefined || wsId < 0) return [];   // no real current ws → show nothing
        const out = [];
        for (const w of (Hyprland.toplevels?.values || [])) {
            const ipc = w?.lastIpcObject;
            const wid = (w?.workspace?.id) ?? (ipc?.workspace?.id);
            if (wid === undefined || wid < 0) continue;   // unknown or special
            if (wid !== wsId) continue;                    // different workspace
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
