// Passive peek cheatsheet. Sibling to CheatSheet.qml, but deliberately the
// opposite in feel: no dim backdrop, no keyboard focus, no click-to-dismiss. It
// is a hands-off contextual reference that fades in at the screen edge when you
// dwell in a submap, so you can read the binds while still seeing and using the
// window underneath.
//
// Driven entirely by Hyprland's submap event system (hypr/events/peek.lua):
//   qs -c quantumfate ipc call cheatsheetPeek show|hide|toggle
// The Lua side arms a delay on submap entry and hides on the next transition;
// this surface only renders whatever the current submap's binds are.
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

    // Same live context as CheatSheet.qml, its sibling — see there for why the
    // probe is event-driven rather than timer- or show()-driven.
    property var ctx: ({ workspace: "", windowClass: "", grouped: false, gaming: false, layout: "" })
    readonly property string breadcrumb: CheatParse.breadcrumb(ctx)

    // Raw `hyprctl binds -j` text, cached across opens/submap changes — see
    // CheatSheet.qml, its sibling, for why (the bind table only changes on a
    // config reload, so re-shelling out on every dwell/traversal is pure
    // latency for no new information).
    property string bindsJson: ""
    property bool bindsValid: false

    // Preferred category ordering; unlisted categories sort alphabetically after.
    readonly property var categoryOrder: [
        "Window", "Workspace", "Menus", "Media", "Utilities", "Dofus", "Shell", "General"
    ]

    // NB: `qs ipc call <target> show` is swallowed by the quickshell CLI (it
    // prints the target interface instead of invoking), so the peek exposes
    // open/close instead — driven from hypr/events/peek.lua.
    IpcHandler {
        target: "cheatsheetPeek"
        function toggle(): void { scope.shown ? scope.close() : scope.open(); }
        function open(): void { scope.open(); }
        function close(): void { scope.close(); }
    }

    function open() {
        if (scope.bindsValid) scope.cats = CheatParse.parse(scope.bindsJson, scope.submap, scope.categoryOrder, scope.ctx);
        else refresh.running = true;
        scope.shown = true;
    }
    function close() { scope.shown = false; }

    // Track the active submap so a show renders the right context. Also drives
    // live follow-along if the submap changes while the peek is visible.
    // `configreloaded` invalidates the cache above — the Lua side
    // (hypr/events/peek.lua) already closes the panel on reload so it can
    // never be orphaned; this only keeps the bind table itself fresh.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") scope.submap = event.data; // "" at root
            else if (event.name === "configreloaded") scope.bindsValid = false;
            // Same event set as CheatSheet.qml's ctxProbe trigger — see there.
            else if (event.name === "activewindow" || event.name === "activewindowv2"
                || event.name === "workspace" || event.name === "workspacev2"
                || event.name === "changefloatingmode" || event.name === "fullscreen")
                ctxProbe.running = true;
        }
    }
    Component.onCompleted: ctxProbe.running = true
    onSubmapChanged: if (scope.shown) {
        if (scope.bindsValid) scope.cats = CheatParse.parse(scope.bindsJson, scope.submap, scope.categoryOrder, scope.ctx);
        else refresh.running = true;
    }
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

    // Probes `activewindow` then `activeworkspace` — see CheatSheet.qml's
    // ctxProbe/layoutProbe pair for the full rationale (event-driven, chained,
    // never on the open path).
    Process {
        id: ctxProbe
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                var w;
                try { w = JSON.parse(text); } catch (e) { return; }
                if (!w || Object.keys(w).length === 0) {
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
        // Stay mapped until the fade-out finishes, so closing actually animates
        // (unmapping the moment `shown` flips false would just pop it away).
        visible: scope.shown || card.opacity > 0
        color: "transparent"
        // Bottom-centre of the screen, sized to content — never fullscreen, so the
        // rest of the screen (and its window) stays visible and interactive.
        anchors { bottom: true }
        margins { bottom: Theme.gap * 12 }
        implicitWidth: card.implicitWidth
        implicitHeight: card.implicitHeight
        exclusiveZone: 0                                   // don't reserve space / shove tiling
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None // never steal focus / eat input
        WlrLayershell.namespace: "quickshell-cheatsheet-peek"  // targeted by hypr layerrules

        Surface {
            id: card
            // Fixed width: the two-column layout uses fillWidth children, which
            // have no intrinsic width, so the card must define it (content-sizing
            // would collapse). Height still follows content.
            implicitWidth: 600
            implicitHeight: Math.min(header.implicitHeight + contextLine.implicitHeight
                + cols.implicitHeight + 3 * Theme.pad, 900)
            elevation: "peek"
            radius: Theme.radius

            // Almost-instant fade in, gentler fade out. The compositor maps this
            // layer with no animation (see hypr layerrules) so the fade is owned
            // here, giving independent in/out timing.
            opacity: scope.shown ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: scope.shown ? 70 : 320; easing.type: Easing.OutQuad }
            }

            ColumnLayout {
                anchors { fill: parent; margins: Theme.pad }
                spacing: Theme.gap

                Text {
                    id: header
                    text: scope.submap === "" ? "Keybinds" : "Keybinds · " + scope.submap
                    color: Theme.accent
                    font { pixelSize: Theme.fs.lg; bold: true }
                }

                Text {
                    id: contextLine
                    text: scope.breadcrumb
                    color: Theme.subtextAlt
                    font.pixelSize: Theme.fs.xs
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }

                // Two balanced columns, each a stack of category sections. Sized to
                // content (no scroll) — the peek is a glance, not a full browse.
                RowLayout {
                    id: cols
                    Layout.fillWidth: true
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
                                                    font { pixelSize: Theme.fs.xs; family: "monospace" }
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: rowDelegate.modelData.desc
                                                color: Theme.text
                                                font.pixelSize: Theme.fs.sm
                                                elide: Text.ElideRight
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
                    font.pixelSize: Theme.fs.sm
                }
            }
        }
    }
}
