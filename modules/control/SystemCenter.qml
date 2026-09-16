// System Center (LEO-226) — the settings that used to sit in the bar, now a
// panel: what each adapter DID last time, how DEW it did it, and a way to
// re-run it — with one row per adapter and the whole surface navigable from
// the keyboard (arrows move the selection, Enter restarts the selected
// adapter, Escape closes; the Dofus panel's row-parity rule).
//
// Adapter registry for this slice:
//   theme        — `,theme.sh apply`; render AdapterResult (tiers, pending,
//                  failed) and restart by re-running the same command
//   scene policy — scene-policy/last.json; restart `,scene-apply.sh <mode>`
// The registry is data so an adapter landing is a row, not a code tour.
//
// Honesty rules carried over: a never-run adapter reports `never applied`,
// a DEAD one renders `unavailable (Ns ago)` — never a spinner, never blank.
//
// No dim backdrop: the System Center is context, not a modal (the done-when
// row is explicit), and it opens on the intended monitor — the anchor screen
// the bus carries — and stays put without an explicit action.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // AdapterResult, PanelBus, Theme, Focus
import "../common"        // Surface
import "ControlLogic.js" as ControlLogic

Scope {
    id: scope

    // The visible state, owned here so the bar entry and the IPC share truth.
    property bool shown: false
    property int selected: 0

    // Adapter rows, newest-known results first. Each row owns its RESTART
    // command; the registry is deliberate about the two the desk ships.
    readonly property var rows: [
        {
            name: "theme",
            label: "Theme fan-out",
            subtitle: "kitty, GTK, Qt, Hyprland, wallpapers",
            ok: AdapterResult.ok,
            ts: AdapterResult.ts,
            summary: AdapterResult.everRan ? AdapterResult.tierSummary : "never on this machine",
            restart: [",theme.sh", "apply"],
        },
        {
            name: "scene-policy",
            label: "Scene policy apply",
            subtitle: "user-unit background work",
            ok: true,
            ts: scope.sceneLast.ts ?? 0,
            summary: (scope.sceneLast.mode ?? "")
                ? (scope.sceneLast.mode + " applied" + ((scope.sceneLast.vetoes ?? []).length ? " · " + (scope.sceneLast.vetoes ?? []).length + " vetoes honoured" : ""))
                : "never on this machine",
            restart: [",scene-apply.sh", scope.sceneLast.mode || "neutral"],
        },
    ]
    // scene-policy's own reader surface (LEO-241): watched like
    // theme.result.json is, once per apply.
    property var sceneLast: (sceneLastFile.text() || "{}")
    FileView {
        id: sceneLastFile
        path: Quickshell.env("QF_STORE") || (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quantum-store/scene-policy/last.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { scope.sceneLast = JSON.parse((text() || "{}")); } catch (e) { console.warn("systemcenter: bad last.json"); }
        }
        onLoadFailed: () => {}   // no apply yet is not an error state
    }

    function agoShown(ts) {
        if (!ts) return "";
        const s = Math.max(0, Math.floor(Date.now() / 1000) - ts);
        if (s < 45) return "just now";
        if (s < 3600) return s < 60 ? s + "s ago" : Math.floor(s / 60) + "m ago";
        if (s < 86400) return Math.floor(s / 3600) + "h ago";
        return "unavailable (" + s + "s ago)";
    }

    function open() {
        if (scope.shown) return;
        scope.shown = true;
    }
    function close() { scope.shown = false; scope.selected = 0; }

    // Restart the SELECTED adapter. A restart re-runs the command the adapter
    // last ran; its honesty lands exactly where the last result did.
    function restartSelected() {
        const row = scope.rows[scope.selected];
        if (!row) return;
        restart.command = [row.restart[0], row.restart[1]];
        restart.running = true;
    }
    Process { id: restart; command: [",theme.sh", "apply"] }

    IpcHandler {
        target: "systemcenter"
        function toggle(): void { scope.shown ? scope.close() : scope.open(); }
    }

    PanelWindow {
        visible: scope.shown
        screen: PanelBus.screenObject(PanelBus.activeScreen)
        color: "transparent"
        anchors { top: true; bottom: true; right: true }
        // Explicit size hint: with only a right edge anchored, the window would
        // otherwise size to its content, and the content's width reads the
        // window width — a cycle that collapses the dock to a sliver. The
        // anchoring engine sizes the window from this hint.
        implicitWidth: screen ? Math.min(screen.width * 0.34, 480) : 480
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-systemcenter"

        // No dim backdrop (LEO-226's explicit rule): the panel is information,
        // and a click outside simply closes it through a full-screen grab
        // that never dims.
        MouseArea { anchors.fill: parent; onClicked: scope.close() }

        onVisibleChanged: if (visible) keys.forceActiveFocus()

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: scope.close()
            Keys.onDownPressed: scope.selected = ControlLogic.moveSelectionIndex(scope.selected, "down", scope.rows.length)
            Keys.onUpPressed: scope.selected = ControlLogic.moveSelectionIndex(scope.selected, "up", scope.rows.length)
            Keys.onReturnPressed: scope.restartSelected()
            Keys.onEnterPressed: scope.restartSelected()

            Surface {
                anchors.fill: parent
                elevation: "modal"
                radius: 0

                ColumnLayout {
                    anchors { fill: parent; margins: Theme.pad }
                    spacing: Theme.gap

                    Text {
                        text: "System Center"
                        color: Theme.accent
                        font { pixelSize: Theme.fs.xl; bold: true }
                    }

                    // Every adapter, its last result and age. Dead ones render
                    // `unavailable (…)` in place, never a spinner or a blank.
                    Repeater {
                        model: scope.rows
                        delegate: Rectangle {
                            id: rowCard
                            required property var modelData
                            required property int index
                            readonly property bool selected: rowCard.index === scope.selected
                            Layout.fillWidth: true
                            implicitHeight: rowLayout.implicitHeight + 16
                            radius: Theme.radiusSmall
                            color: rowCard.selected ? Theme.withAlpha(Theme.accent, 0.14) : Theme.surface
                            border { width: 1; color: rowCard.selected ? Theme.accent : Theme.border }

                            ColumnLayout {
                                id: rowLayout
                                anchors { fill: parent; margins: Theme.space.md }
                                spacing: Theme.space.xs
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.space.md
                                    Rectangle { implicitWidth: 6; implicitHeight: 6; radius: 3; color: Theme.accent }
                                    Text {
                                        text: rowCard.modelData.label
                                        color: Theme.text
                                        font { pixelSize: Theme.fs.md; weight: Theme.barFontWeight }
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: rowCard.modelData.ok
                                            ? "ok · "
                                            : "unavailable · "
                                        color: rowCard.modelData.ok ? Theme.success : Theme.error
                                        font.pixelSize: Theme.fs.xs
                                    }
                                    Text {
                                        text: scope.agoShown(rowCard.modelData.ts)
                                        color: Theme.subtext
                                        font.pixelSize: Theme.fs.xs
                                        Layout.rightMargin: Theme.space.sm
                                    }
                                }
                                Text {
                                    text: rowCard.modelData.summary
                                    color: Theme.subtext
                                    font.pixelSize: Theme.fs.sm
                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                    Layout.fillWidth: true
                                }
                                Text {
                                    visible: (AdapterResult.pendingSummary ?? "") !== ""
                                        && rowCard.modelData.name === "theme"
                                    text: AdapterResult.pendingSummary
                                    color: Theme.warning
                                    font.pixelSize: Theme.fs.xs
                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: "enter: restart"
                                    color: Theme.subtextAlt
                                    font.pixelSize: Theme.fs.xs
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
