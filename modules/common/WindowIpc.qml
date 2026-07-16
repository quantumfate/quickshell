// Window title control over IPC. Renames the focused window's title, the same
// mechanism the Dofus launch flow uses (xdotool set_window), but on demand for
// any window:
//
//   qs -c quantumfate ipc call window rename "My Title"
//
// Works on XWayland windows (e.g. Dofus clients); native Wayland toplevels
// don't expose an externally-settable title. Focus the target, then rename.
import Quickshell
import Quickshell.Io

Scope {
    Process { id: proc }

    IpcHandler {
        target: "window"

        // Rename the currently active window. Title is passed as an argv element
        // ($1), never interpolated into the script, so it is injection-safe.
        function rename(title: string): void {
            proc.command = [
                "bash", "-c",
                "xdotool set_window --name \"$1\" \"$(xdotool getactivewindow)\"",
                "qfs-window-rename", title
            ];
            proc.running = true;
        }
    }
}
