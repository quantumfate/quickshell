// Dofus Class Assigner — a standalone panel whose single job is binding each
// character to a class. One row per pool character: the name, the teams it
// belongs to, its current class icon, and a dropdown (icon + name items) that
// writes DofusState.setClass. Purely a view over team.json's `classes` map;
// the Team Manager (TeamSelector) stays the place for roster editing.
//
//   qs -c quantumfate ipc call classAssigner toggle | show | hide
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
// Basic style so the ComboBox's contentItem/background are fully re-themable.
import QtQuick.Controls.Basic as QC
import "../../services"
import "../common"   // ClassIcon

Scope {
    id: scope

    property bool shown: false
    // A ComboBox popup renders outside `card`, so widen the input mask while one
    // is open (else its items fall through the layer and aren't clickable).
    property bool _popupOpen: false
    // Hiding the panel can skip a popup's onClosed, leaving _popupOpen stuck true
    // -> the (now re-shown) full-screen overlay would eat all input. Clear it.
    onShownChanged: if (!shown) _popupOpen = false

    IpcHandler {
        target: "classAssigner"
        function toggle(): void { scope.shown = !scope.shown; }
        function show(): void { scope.shown = true; }
        function hide(): void { scope.shown = false; }
    }

    // Team keys a character belongs to, in pill order (Object key order).
    function _teamsOf(name) {
        const out = [];
        const teams = DofusState.teams || ({});
        for (const k of Object.keys(teams)) {
            if ((teams[k] || []).indexOf(name) >= 0) out.push(k);
        }
        return out;
    }

    // One class option row: icon (blank for "") + class name / "no class".
    // Hoisted to scope level because inline components can't nest.
    component ClassOption: RowLayout {
        property string key
        property bool current
        spacing: 8
        ClassIcon {
            cls: key
            size: 22
            Layout.preferredWidth: visible ? size : 0
            Layout.preferredHeight: size
        }
        Text {
            text: key === "" ? "no class" : DofusClasses.nameFor(key)
            color: current ? Theme.accent : (key === "" ? Theme.overlay : Theme.text)
            font.pixelSize: 12
            verticalAlignment: Text.AlignVCenter
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }

    // Class chooser: icon + name items, "" = no class. Re-themed Basic ComboBox.
    component ClassPicker: QC.ComboBox {
        id: cp
        property string value: ""                                    // current class key
        signal picked(string key)
        readonly property var keys: [""].concat(DofusClasses.keys)   // options, blank first
        model: keys
        currentIndex: Math.max(0, keys.indexOf(value))
        implicitHeight: 28
        implicitWidth: 150
        onActivated: (i) => cp.picked(cp.keys[i])
        contentItem: ClassOption { key: cp.value; current: false; anchors { left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 18 } }
        indicator: Text {
            x: cp.width - width - 8; y: (cp.height - height) / 2
            text: "▾"; color: Theme.subtext; font.pixelSize: 11
        }
        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.background
            border { width: 1; color: cp.activeFocus ? Theme.accent : Theme.border }
        }
        delegate: QC.ItemDelegate {
            required property var modelData
            required property int index
            width: cp.width
            contentItem: ClassOption { key: modelData; current: index === cp.currentIndex; anchors { left: parent.left; leftMargin: 6; right: parent.right; rightMargin: 6 } }
            background: Rectangle { color: highlighted ? Theme.surfaceAlt : Theme.background }
            highlighted: cp.highlightedIndex === index
        }
        popup: QC.Popup {
            y: cp.height
            width: cp.width
            implicitHeight: Math.min(contentItem.implicitHeight, 300)
            padding: 1
            onOpened: scope._popupOpen = true
            onClosed: scope._popupOpen = false
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: cp.delegateModel
                currentIndex: cp.highlightedIndex
                QC.ScrollBar.vertical: QC.ScrollBar {}
            }
            background: Rectangle {
                color: Theme.background
                border { width: 1; color: Theme.border }
                radius: Theme.radiusSmall
            }
        }
    }

    PanelWindow {
        id: win
        visible: scope.shown
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-class-assigner"

        // Only `card` captures input, except while a dropdown popup is open.
        mask: scope._popupOpen ? null : cardRegion
        Region { id: cardRegion; item: card }

        Rectangle {
            id: card
            x: (win.width - width) / 2
            y: 60
            width: 620
            height: Math.min(win.height - 120, body.implicitHeight + 2 * Theme.pad)
            radius: Theme.radius
            color: Theme.withAlpha(Theme.background, 0.97)
            border { width: 1; color: Theme.border }

            // Drag the card by its top strip.
            MouseArea {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 30
                cursorShape: Qt.SizeAllCursor
                property real _lastX: 0
                property real _lastY: 0
                onPressed: (mouse) => { _lastX = mouse.x; _lastY = mouse.y }
                onPositionChanged: (mouse) => {
                    card.x = Math.max(0, Math.min(win.width - card.width, card.x + mouse.x - _lastX));
                    card.y = Math.max(0, Math.min(win.height - card.height, card.y + mouse.y - _lastY));
                }
            }

            Flickable {
                id: flick
                anchors { fill: parent; margins: Theme.pad }
                contentWidth: width
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                QC.ScrollBar.vertical: QC.ScrollBar { policy: QC.ScrollBar.AsNeeded }

                ColumnLayout {
                    id: body
                    width: flick.width
                    spacing: Theme.gap

                    // ── Header ──────────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle { width: 10; height: 10; radius: 5; color: Theme.accent }
                        Text {
                            text: "Character Classes"
                            color: Theme.text
                            font { pixelSize: 16; bold: true; family: Theme.fontFamily }
                        }
                        Text {
                            text: "assign a class to each character"
                            color: Theme.overlay
                            font.pixelSize: 11
                            Layout.fillWidth: true
                        }
                        Text {
                            text: DofusState.pool.length + " chars"
                            color: Theme.overlay
                            font.pixelSize: 11
                        }
                    }

                    // ── One row per character ───────────────────────────────
                    Repeater {
                        model: DofusState.pool

                        Rectangle {
                            id: row
                            required property string modelData
                            readonly property string cls: DofusState.classOf(modelData)
                            readonly property var inTeams: scope._teamsOf(modelData)
                            Layout.fillWidth: true
                            implicitHeight: 56
                            radius: Theme.radiusSmall
                            color: Theme.surface
                            border { width: 1; color: Theme.border }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 10

                                // Current class emblem (mauve); a same-size slot keeps
                                // names aligned whether or not a class is set.
                                Item {
                                    Layout.preferredWidth: 32; Layout.preferredHeight: 32
                                    ClassIcon {
                                        anchors.centerIn: parent
                                        cls: row.cls
                                        size: 32
                                    }
                                }

                                // Name + team-membership badges beneath.
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: row.modelData
                                        color: Theme.text
                                        font { pixelSize: 14; bold: true }
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        // "Unassigned" hint when the character is on no team.
                                        Text {
                                            visible: row.inTeams.length === 0
                                            text: "on no team"
                                            color: Theme.overlay
                                            font.pixelSize: 10
                                        }
                                        Repeater {
                                            model: row.inTeams
                                            Rectangle {
                                                required property string modelData
                                                readonly property bool active: modelData === DofusState.selected
                                                implicitWidth: badge.implicitWidth + 12
                                                implicitHeight: 16
                                                radius: Theme.radiusPill
                                                color: active ? Theme.withAlpha(Theme.accent, 0.22) : Theme.surfaceAlt
                                                border { width: 1; color: active ? Theme.accent : Theme.border }
                                                Text {
                                                    id: badge
                                                    anchors.centerIn: parent
                                                    text: parent.modelData
                                                    color: parent.active ? Theme.accent : Theme.subtext
                                                    font.pixelSize: 10
                                                }
                                            }
                                        }
                                    }
                                }

                                // The class setter for this character.
                                ClassPicker {
                                    value: row.cls
                                    onPicked: (key) => DofusState.setClass(row.modelData, key)
                                }
                            }
                        }
                    }

                    Text {
                        visible: DofusState.pool.length === 0
                        text: "No characters in the pool — add some in the Team Manager first."
                        color: Theme.overlay
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
