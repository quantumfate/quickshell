pragma Singleton
// Hypr — window actions over Hyprland's Lua dispatch layer.
//
// This compositor evaluates `dispatch <x>` as `hl.dispatch(<x>)` (see
// docs/dofus-feature-manifest.md), so every action sends a Lua expression, and
// windows are addressed by a SELECTOR string ("address:0x…" or "title:…").
// Generic enough for any taskbar; DofusWindows builds title selectors on top.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Singleton {
    id: root

    // Focus a window by selector and raise it (raise is a no-op when tiled).
    function focus(selector) {
        if (!selector) return;
        Hyprland.dispatch("hl.dsp.focus({ window = [[" + selector + "]] })");
        Hyprland.dispatch("hl.dsp.window.bring_to_top()");
    }

    // Close a window: focus it, then close the now-active one (hl.dsp.window.close
    // has no selector form here).
    function close(selector) {
        if (!selector) return;
        Hyprland.dispatch("hl.dsp.focus({ window = [[" + selector + "]] })");
        Hyprland.dispatch("hl.dsp.window.close()");
    }

    // Retitle an XWayland window by pid (same mechanism as WindowRename).
    Process { id: retitleProc }
    function retitle(pid, title) {
        if (!(pid > 0) || !title) return;
        retitleProc.command = [
            "bash", "-c",
            "xdotool set_window --name \"$1\" \"$(xdotool search --pid \"$2\" | head -1)\"",
            "qfs-retitle", title, String(pid)
        ];
        retitleProc.running = true;
    }
}
