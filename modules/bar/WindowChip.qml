// WindowChip — one window in a taskbar strip, generic across window classes.
// Which buttons appear is driven by the `show*` flags the strip sets (a button
// shows only when its action is wired). Click the name to focus, double-click to
// rename (when allowed). Width wraps its content — buttons hug the text.
//
// Capture feedback (busy / ✓ / ✗) is Dofus-only and appears when `showCapture`.
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, DofusSwap, BarInput
import "../common"        // ClassIcon

Rectangle {
    id: chip

    // Resolved window: { name, present, focused, selector, pid }.
    required property var slot

    // Screen this chip lives on — routes its tooltips to the right TipLayer.
    property string screenName: ""

    // Highlight the focused window (accent). Off for the plain default taskbar.
    property bool highlightActive: true

    // Action availability (set by the strip; a false flag hides the button).
    property bool showRename: false
    property bool showReorder: false
    property bool canLeft: false
    property bool canRight: false
    property bool showClose: false
    property bool showCapture: false

    signal focusRequested()
    signal renameRequested(string text)
    signal reorderRequested(int dir)     // -1 left, +1 right
    signal closeRequested()
    signal captureRequested()

    readonly property bool present: slot.present
    // `focused` gates the accent styling; suppressed when highlightActive is off.
    readonly property bool focused: slot.focused && chip.highlightActive

    // Dofus capture feedback: "" idle · flash "ok"/"fail" ~1.4s after a learn.
    property string flash: ""
    readonly property bool busy: showCapture && DofusSwap.capturing === slot.name
    Timer { id: flashTimer; interval: 1400; onTriggered: chip.flash = "" }
    Connections {
        enabled: chip.showCapture
        target: DofusSwap
        function onCaptured(name, ok) {
            if (name !== chip.slot.name) return;
            chip.flash = ok ? "ok" : "fail";
            flashTimer.restart();
        }
    }

    implicitWidth: rowContent.implicitWidth + 12
    implicitHeight: 24
    radius: Theme.radiusSmall
    color: focused ? Theme.withAlpha(Theme.accent, 0.25)
         : hover.hovered ? Theme.surfaceAlt
         : present ? Theme.surface : "transparent"
    border {
        width: (busy || flash !== "") ? 2 : 1
        color: flash === "ok" ? Theme.success
             : flash === "fail" ? Theme.error
             : busy ? Theme.warning
             : focused ? Theme.accent
             : present ? Theme.border : Theme.withAlpha(Theme.border, 0.4)
    }
    opacity: present ? 1.0 : 0.5

    HoverHandler { id: hover }

    RowLayout {
        id: rowContent
        anchors { fill: parent; leftMargin: 8; rightMargin: 4 }
        spacing: 4

        // Class emblem (mauve) — auto-hides when this character has no class set.
        ClassIcon {
            cls: DofusState.classOf(chip.slot.name)   // DofusState is a singleton
            size: 18
            Layout.preferredWidth: visible ? size : 0
            Layout.preferredHeight: size
            Layout.alignment: Qt.AlignVCenter
        }

        // Dofus learned-hash dot (only when capture is enabled, on a team slot —
        // an unmatched/un-named window has no roster identity to learn).
        Rectangle {
            visible: chip.showCapture && chip.slot.team
            width: 6; height: 6; radius: 3
            color: DofusSwap.learned(chip.slot.name) ? Theme.success : Theme.overlay
            Layout.alignment: Qt.AlignVCenter
            HoverHandler { id: dotHover }
            HoverTip {
                shown: dotHover.hovered; screenName: chip.screenName
                text: DofusSwap.learned(chip.slot.name)
                    ? "Turn-hash learned — swap can recognise " + chip.slot.name
                    : "No turn-hash yet — use ◎ during this character's turn"
            }
        }

        // Name — click focuses, double-click renames (when allowed).
        Text {
            id: label
            visible: !editor.visible
            text: chip.slot.name
            color: chip.focused ? Theme.accent : Theme.text
            font { family: Theme.fontFamily; pixelSize: 12; bold: chip.focused }
            elide: Text.ElideRight
            Layout.maximumWidth: 220
            verticalAlignment: Text.AlignVCenter

            TapHandler {
                acceptedButtons: Qt.LeftButton
                onSingleTapped: chip.focusRequested()
                onDoubleTapped: if (chip.showRename) chip.beginRename()
            }
            HoverHandler { id: labelHover }
            HoverTip {
                shown: labelHover.hovered; screenName: chip.screenName
                text: chip.showRename ? "Click: focus + raise · Double-click: rename" : "Click: focus + raise"
            }
        }

        TextInput {
            id: editor
            visible: false
            color: Theme.text
            font { family: Theme.fontFamily; pixelSize: 12 }
            Layout.preferredWidth: Math.max(60, label.implicitWidth)
            verticalAlignment: TextInput.AlignVCenter
            clip: true; selectByMouse: true
            onEditingFinished: chip.commitRename()
            Keys.onEscapePressed: chip.cancelRename()
        }

        ChipButton {
            visible: chip.showCapture && chip.slot.team; symbol: "◎"; enabled: DofusSwap.calibrated
            tip: "Capture turn-hash for " + chip.slot.name + " (press during their turn)"
            onActivated: chip.captureRequested()
        }
        ChipButton {
            visible: chip.showReorder && chip.slot.team; symbol: "◀"; enabled: chip.canLeft
            onActivated: chip.reorderRequested(-1)
        }
        ChipButton {
            visible: chip.showReorder && chip.slot.team; symbol: "▶"; enabled: chip.canRight
            onActivated: chip.reorderRequested(1)
        }
        ChipButton {
            visible: chip.showClose; symbol: "✕"; enabled: chip.present
            onActivated: chip.closeRequested()
        }
    }

    // Capture feedback: color wash only (no text — the toast carries the words).
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: chip.busy || chip.flash !== ""
        color: chip.flash === "ok" ? Theme.withAlpha(Theme.success, 0.28)
             : chip.flash === "fail" ? Theme.withAlpha(Theme.error, 0.28)
             : Theme.withAlpha(Theme.warning, 0.20)
    }

    // Guards against the focus-loss editingFinished re-firing commit after we've
    // already committed/cancelled (hiding the field drops focus).
    property bool _renaming: false

    function beginRename() {
        BarInput.begin(chip.screenName);   // let THIS screen's bar grab the keyboard
        chip._renaming = true;
        // Team chips prefill their name; an un-named window starts blank (its
        // label is the "unnamed" placeholder, not a real name to edit).
        editor.text = chip.slot.team ? chip.slot.name : "";
        editor.visible = true;
        // Defer the focus grab until after the layer surface has switched to
        // Exclusive keyboard focus, else the keys have nowhere to land.
        Qt.callLater(() => { editor.forceActiveFocus(); editor.selectAll(); });
    }
    function commitRename() {
        if (!chip._renaming) return;
        chip._renaming = false;
        editor.visible = false;
        BarInput.end();
        chip.renameRequested(editor.text);
    }
    function cancelRename() {
        chip._renaming = false;
        editor.visible = false;
        BarInput.end();
    }

    // If the chip is torn down mid-rename (window closed, strip rebuilt), make
    // sure we release the keyboard grab — never leave the bar holding focus.
    Component.onDestruction: if (chip._renaming) BarInput.end();

    // A tiny square action button; greys out and ignores clicks when disabled.
    // `tip` (optional) explains a non-obvious action, rendered below the bar.
    component ChipButton: Rectangle {
        property string symbol
        property bool enabled: true
        property string tip: ""
        signal activated
        Layout.preferredWidth: 18; Layout.preferredHeight: 18
        radius: Theme.radiusSmall
        color: btnHover.containsMouse && enabled ? Theme.overlay : "transparent"
        Text {
            anchors.centerIn: parent; text: parent.symbol
            color: parent.enabled ? Theme.subtext : Theme.withAlpha(Theme.subtext, 0.3)
            font.pixelSize: 10
        }
        MouseArea {
            id: btnHover; anchors.fill: parent; hoverEnabled: true
            onClicked: if (parent.enabled) parent.activated()
        }
        HoverTip { shown: btnHover.containsMouse && parent.tip !== ""; text: parent.tip; screenName: chip.screenName }
    }
}
