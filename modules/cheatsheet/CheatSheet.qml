// Keybind cheatsheet overlay: a which-key style render of the Hyprland
// submap tree. Reads `hyprctl binds -j` (descriptions come from the Lua bind
// layer) and renders a themed panel instead of the old ,cheatsheet.sh dmenu.
//
// Context-aware: at root it shows global binds; inside a submap it shows only
// that submap's own binds (matching the old script's filtering). Nesting
// itself is Hyprland's: `hypr/hypr/lib/submap.lua` owns the stack and binds
// escape to `M.back()` in every submap, so "back one level from any depth"
// is already correct as long as this overlay just follows the submap events
// it is sent — which is all it does below.
//
// Binds are grouped into categories (derived from their descriptions) and
// sorted for tidiness.
//
// Toggle from Hyprland:  qs -c quantumfate ipc call cheatsheet toggle
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"
import "../common"        // Surface
import "CheatParse.js" as CheatParse

Scope {
    id: scope

    property bool shown: false
    property string submap: ""          // "" = root/default
    property var cats: []               // [{ name, rows: [{ combo, desc }] }]
    readonly property var columns: CheatParse.splitColumns(cats)  // [leftCats, rightCats]

    // The desk's live four-tuple context, re-probed on focus/workspace change
    // (never a timer, never from show() — see ctxProbe below) and fed to
    // CheatParse.parse so a bind that doesn't apply here is hidden outright.
    property var ctx: ({ workspace: "", windowClass: "", grouped: false, gaming: false, layout: "" })
    readonly property string breadcrumb: CheatParse.breadcrumb(ctx)

    // Raw `hyprctl binds -j` text, fetched once and reused for every submap:
    // the bind table itself only changes on a config reload, so re-shelling
    // out on every nesting step is pure latency for no new information.
    property string bindsJson: ""
    property bool bindsValid: false

    // Preferred category ordering; unlisted categories sort alphabetically after.
    readonly property var categoryOrder: [
        "Window", "Workspace", "Menus", "Media", "Utilities", "Dofus", "Shell", "General"
    ]

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { scope.shown ? scope.hide() : scope.show(); }
        function show(): void { scope.show(); }
        function hide(): void { scope.hide(); }
    }

    // Opening is on the input path, so it must never wait on a process: reuse
    // the cached bind table (parsing is pure JS, effectively instant) and only
    // fall back to `hyprctl` the first time, or after a config reload has
    // invalidated it.
    function show() {
        // Fresh open: drop the previous session's reserved height so this one
        // starts from its own content rather than inheriting a stale high
        // watermark (the "never shrink while open" rule only applies within
        // one open session, not across separate ones).
        if (!scope.shown) card.resetReserve = true;
        if (scope.bindsValid) scope.cats = CheatParse.parse(scope.bindsJson, scope.submap, scope.categoryOrder, scope.ctx);
        else refresh.running = true;
        scope.shown = true;
    }
    function hide() { scope.shown = false; }

    // Keep the active submap current so a toggle shows the right context, and
    // close on a config reload so the overlay can never be orphaned on screen.
    // Hyprland's `hypr/hypr/events/peek.lua` hit exactly this bug for the peek
    // panel: a reload resets the Lua submap stack while the Quickshell surface
    // stays mapped, so nothing is left to ever ask it to close.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") scope.submap = event.data; // "" at root
            else if (event.name === "configreloaded") { scope.bindsValid = false; scope.hide(); }
            // Context only changes on a focus/workspace/layout transition, so
            // only these events re-probe it — never a timer, never show().
            else if (event.name === "activewindow" || event.name === "activewindowv2"
                || event.name === "workspace" || event.name === "workspacev2"
                || event.name === "changefloatingmode" || event.name === "fullscreen")
                ctxProbe.running = true;
        }
    }
    Component.onCompleted: ctxProbe.running = true

    // Which-key follow-along: while open, traversing submaps re-renders from
    // the already-cached bind table — no process spawn on the nesting path.
    onSubmapChanged: if (scope.shown) {
        if (scope.bindsValid) scope.cats = CheatParse.parse(scope.bindsJson, scope.submap, scope.categoryOrder, scope.ctx);
        else refresh.running = true;
    }
    // A context change (new focus/workspace) re-filters from the cached bind
    // table too — still no process spawn on this path, only on ctxProbe above.
    onCtxChanged: if (scope.shown && scope.bindsValid)
        scope.cats = CheatParse.parse(scope.bindsJson, scope.submap, scope.categoryOrder, scope.ctx);

    Process {
        id: refresh
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                scope.bindsJson = text;
                scope.bindsValid = true;
                scope.cats = CheatParse.parse(text, scope.submap, scope.categoryOrder, scope.ctx);
            }
        }
    }

    // Probes `activewindow` (class, workspace, group membership) in one shot.
    // Fired only from the rawEvent filter above and once on startup — never a
    // timer, never inside show(), so opening the overlay never waits on it.
    Process {
        id: ctxProbe
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                var w;
                try { w = JSON.parse(text); } catch (e) { return; }
                if (!w || Object.keys(w).length === 0) {
                    // No focused window (e.g. an empty workspace): keep the
                    // workspace/layout probe's data, just clear the window-shaped bits.
                    scope.ctx = Object.assign({}, scope.ctx, { windowClass: "", grouped: false });
                } else {
                    var wsName = (w.workspace && w.workspace.name) || "";
                    scope.ctx = Object.assign({}, scope.ctx, {
                        windowClass: w.class || "",
                        grouped: Array.isArray(w.grouped) && w.grouped.length > 0,
                        workspace: wsName,
                        gaming: wsName === "gaming"
                    });
                }
                layoutProbe.running = true;
            }
        }
    }

    // Layout has no per-window field, so it's a second, equally cheap shot at
    // the active workspace — chained after ctxProbe rather than parallel, so
    // both writes land in one `ctx` update instead of racing each other.
    Process {
        id: layoutProbe
        command: ["hyprctl", "-j", "activeworkspace"]
        stdout: StdioCollector {
            onStreamFinished: {
                var ws;
                try { ws = JSON.parse(text); } catch (e) { return; }
                scope.ctx = Object.assign({}, scope.ctx, { layout: (ws && ws.tiledLayout) || "" });
            }
        }
    }

    PanelWindow {
        visible: scope.shown
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-cheatsheet"   // targeted by hypr layerrules

        // Dim backdrop; click to dismiss.
        Surface {
            anchors.fill: parent
            elevation: "backdrop"
            radius: 0
            border.width: 0
            MouseArea { anchors.fill: parent; onClicked: scope.hide() }
        }

        Surface {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.62, 960)

            // A nested node has fewer rows than its parent almost always, so
            // sizing to the live content would shrink the card on every
            // descent and grow it back on every "back" — a layout jump under
            // the cursor on the one interaction (nesting) that must feel
            // static. Instead the card reserves the tallest size it has
            // needed so far and only grows into a taller one, smoothly; it
            // never shrinks back while open, so descending never moves
            // anything under the pointer.
            readonly property real contentHeight: header.implicitHeight + contextLine.implicitHeight
                + divider.implicitHeight + cols.implicitHeight + footer.implicitHeight + 4 * body.spacing
            property real reservedHeight: contentHeight
            // Set by show() on a fresh open, so this session starts from its
            // own content instead of inheriting the previous session's high
            // watermark — snapped in place (behavior off) rather than grown
            // into, since an open must show the right size immediately.
            property bool resetReserve: false
            onContentHeightChanged: {
                if (resetReserve) {
                    reservedBehavior.enabled = false;
                    reservedHeight = contentHeight;
                    reservedBehavior.enabled = true;
                    resetReserve = false;
                } else if (contentHeight > reservedHeight) {
                    reservedHeight = contentHeight;
                }
            }
            Behavior on reservedHeight { id: reservedBehavior; NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }

            height: Math.min(parent.height * 0.85, reservedHeight + 2 * Theme.pad)
            elevation: "modal"
            radius: Theme.radius

            ColumnLayout {
                id: body
                anchors { fill: parent; margins: Theme.pad }
                spacing: Theme.gap

                Text {
                    id: header
                    text: scope.submap === "" ? "Keybinds" : "Keybinds · " + scope.submap
                    color: Theme.accent
                    font { pixelSize: Theme.fs.lg; bold: true }
                }

                // The four-tuple context this render was filtered against —
                // workspace > class > group > layout.
                Text {
                    id: contextLine
                    text: scope.breadcrumb
                    color: Theme.subtextAlt
                    font.pixelSize: Theme.fs.xs
                }

                Rectangle { id: divider; Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: cols.implicitHeight
                    clip: true

                    // Two balanced columns, each a stack of category sections.
                    RowLayout {
                        id: cols
                        width: parent.width
                        spacing: Theme.pad * 2

                        Repeater {
                            model: 2
                            delegate: ColumnLayout {
                                id: colDelegate
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1   // equal columns
                                Layout.alignment: Qt.AlignTop
                                spacing: Theme.gap

                                Repeater {
                                    model: scope.columns[colDelegate.index]
                                    delegate: ColumnLayout {
                                        id: categoryDelegate
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: Theme.space.xs

                                        Text {
                                            text: categoryDelegate.modelData.name.toUpperCase()
                                            color: Theme.accentAlt
                                            font { pixelSize: Theme.fs.xs; bold: true; letterSpacing: 1 }
                                            Layout.bottomMargin: Theme.space.xs
                                        }

                                        Repeater {
                                            model: categoryDelegate.modelData.rows
                                            delegate: RowLayout {
                                                id: rowDelegate
                                                required property var modelData
                                                Layout.fillWidth: true
                                                spacing: Theme.gap
                                                Rectangle {
                                                    radius: Theme.radiusSmall
                                                    color: Theme.surface
                                                    implicitWidth: keyText.implicitWidth + 12
                                                    implicitHeight: keyText.implicitHeight + 4
                                                    Text {
                                                        id: keyText
                                                        anchors.centerIn: parent
                                                        text: rowDelegate.modelData.combo
                                                        color: Theme.accent
                                                        font { pixelSize: Theme.fs.sm; family: "monospace" }
                                                    }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: rowDelegate.modelData.desc
                                                    color: Theme.text
                                                    font.pixelSize: Theme.fs.md
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: scope.cats.length === 0
                    text: "No described binds in this context."
                    color: Theme.subtext
                    font.pixelSize: Theme.fs.md
                }

                // Footer legend. Escape's actual behaviour (unwind one level,
                // from any depth) is Hyprland's — every submap.lua tree binds
                // it to `M.back()` — this just states it.
                Text {
                    id: footer
                    text: scope.submap === "" ? "esc close" : "esc back"
                    color: Theme.subtextAlt
                    font.pixelSize: Theme.fs.xs
                }
            }
        }
    }
}
