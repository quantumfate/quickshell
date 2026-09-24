// DofusRoster — Dofus-only bar isle content for the dofus workspace (LEO-234).
//
// This is not attached to a window or Hyprland group; it is bar cluster content
// that mirrors the group order from DofusWindows and exposes the swap-detector
// controls from DofusSwap. It appears only while the active workspace on this
// monitor is the dofus workspace and Dofus clients are present.
//
// Layout per request:
//   [ (class icon, Character) chip, learn button ] ... [ ⌖ ] [ ▶/■ ]
//
// Membership comes from DofusWindows (the live Hyprland group read model), not
// reconstructed anywhere else. Swap state comes from DofusSwap.
//
// LEO-376: the isle used bare Text as its controls — no hover/pressed state,
// no hit target past the glyphs, no focus ring. Every action here now renders
// through DofusRosterButton.qml, the same rounded/alpha-tinted chip idiom as
// modules/common/PalettePicker.qml, so the bar doesn't read as a second
// button language next to the mode panel's. Behaviour is unchanged — same
// DofusWindows.focus/DofusSwap calls as before, just under real controls.
//
// The member rows are that same button too, not a hand-rolled chip with a
// button beside it: emblem and name are one hit target, and the roster is the
// group's tab strip now that the dofus workspace hides Hyprland's own
// groupbar (`engine.hide_groupbar_for` in the hypr repo's host file). Nothing
// else on screen says which client has focus, so the focused member is the
// one filled, bolded, accent-bordered control here — read it as the tab bar
// the compositor stopped drawing.
//
// This is CONTENT, not a card: the bar wraps every isle in its own Surface
// (Bar.qml's `Island`), so this file used to draw a second Surface inside that
// one — a visible frame-within-a-frame around the roster, taller than its
// neighbours and reading as a different widget. It is a bare RowLayout now and
// inherits the bar's material, padding, and height like Workspaces and the
// clock do.
pragma ComponentBehavior: Bound
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, DofusWindows, DofusState, DofusSwap, Tip

RowLayout {
    id: root

    required property var screen
    readonly property var _mon: Hyprland.monitorFor(screen)
    readonly property string _screenName: screen?.name ?? ""

    // The workspace this monitor is actually showing, fed by the bar from the
    // compositor's own raw `workspace`/`focusedmon` events. NOT read from
    // `_mon.activeWorkspace` here: that cached reference goes stale on a
    // same-monitor switch (root-caused in Workspaces.qml's `_activeWsName`
    // header — `focusedmon` does not fire when the focused monitor does not
    // change), and a same-monitor switch onto the dofus workspace is exactly
    // how this isle is reached. Reading the stale reference meant the roster
    // stayed hidden with Dofus up on the workspace it speaks for.
    //
    // The cached reference is still the seed: before the first raw event
    // arrives the bar's map is empty, and the monitor's own answer is right
    // often enough to draw with.
    property string activeWorkspaceName: ""
    readonly property string _wsName: root.activeWorkspaceName !== ""
        ? root.activeWorkspaceName
        : (root._mon?.activeWorkspace?.name ?? "")

    // Visible only on the dofus workspace while Dofus clients are present.
    readonly property bool _onDofus: root._wsName === "dofus"

    // The members this isle speaks for: Dofus clients standing on the very
    // workspace it is drawn over.
    //
    // Joined on the workspace NAME, never an id: a client's workspace object
    // carries `{ address, type, name }` and no `id` at all, so the old id
    // comparison was false on every window and this isle never once became
    // visible with Dofus clients up.
    //
    // The filter is also what keeps held clients out of the strip. A mode
    // that does not admit the dofus workspace parks every client on a hold
    // workspace (hypr/hyprfocus/hold.lua); `DofusWindows` lists a client
    // wherever it stands, deliberately, so an unfiltered roster would offer
    // rows that focus a window the desk has put away.
    readonly property var _members: (DofusWindows.windows ?? []).filter(
        w => w.workspaceName === root._wsName)

    // Whether this isle has anything to say, as a plain fact about the desk.
    //
    // Deliberately NOT read off `visible`: in Qt Quick an item's `visible`
    // reports EFFECTIVE visibility, so a child of a hidden parent reads false
    // no matter what its own binding says. The bar gates the isle's slot on
    // this component ("draw the card only when the roster speaks"), and when
    // that gate read `visible` the two locked each other off — the slot
    // hidden because the roster read hidden, the roster reading hidden
    // because the slot was. The roster never appeared on the dofus workspace,
    // with Dofus up, no matter what the desk published. This property has no
    // such feedback: it depends only on the workspace and the clients.
    readonly property bool shouldShow: root._onDofus && root._members.length > 0
    visible: root.shouldShow

    spacing: Theme.space.lg
    Layout.alignment: Qt.AlignVCenter

    // Roster rows, one per group member in group order — the tab strip
    // the hidden groupbar no longer draws. Each member is one button
    // (class emblem + character name) that focuses the client, carrying
    // its swap-learned state as the corner dot, plus its own "learn".
    Repeater {
        model: root._members

        RowLayout {
            id: chipRow
            required property var modelData
            required property int index
            readonly property bool active: chipRow.modelData.focused ?? false
            readonly property bool named: !!chipRow.modelData.name
            readonly property string character: chipRow.named ? chipRow.modelData.name : ""
            readonly property string cls: chipRow.named ? DofusState.classOf(chipRow.character) : ""
            readonly property bool learned: chipRow.named && DofusSwap.learned(chipRow.character)

            spacing: Theme.space.xs
            Layout.alignment: Qt.AlignVCenter

            DofusRosterButton {
                id: member
                // An unnamed client still gets a slot and a number, so the
                // strip always accounts for every window in the group —
                // the roster is membership, not just the renamed ones.
                text: chipRow.named ? chipRow.character : (chipRow.index + 1) + "."
                iconCls: chipRow.cls
                toggled: chipRow.active
                marked: chipRow.learned
                tooltip: (chipRow.named ? chipRow.character : "unnamed client")
                    + (chipRow.active ? " · focused" : " · click to focus")
                    + (chipRow.learned ? " · turn learned" : "")
                screenName: root._screenName
                Layout.alignment: Qt.AlignVCenter
                onClicked: DofusWindows.focus(chipRow.modelData.selector)
            }

            // Learn button: grab this character's turn-popup hash. Green
            // once a hash exists, so "which of these is still unlearned"
            // is answerable without opening a panel.
            DofusRosterButton {
                visible: chipRow.named
                compact: true
                text: "learn"
                toggled: chipRow.learned
                tone: Theme.c.green
                tooltip: chipRow.learned
                    ? ("Re-learn " + chipRow.character + "'s turn popup")
                    : ("Learn " + chipRow.character + "'s turn popup")
                screenName: root._screenName
                Layout.alignment: Qt.AlignVCenter
                onClicked: DofusSwap.learn(chipRow.character)
            }
        }
    }

    // Separator between roster and controls, in the shell's own divider role
    // rather than a raw palette colour.
    Rectangle {
        visible: controlRow.visible
        Layout.preferredWidth: 1
        Layout.preferredHeight: Theme.barHeight * 0.6
        color: Theme.border
        Layout.alignment: Qt.AlignVCenter
    }

    // Swap-detector controls.
    RowLayout {
        id: controlRow
        spacing: Theme.space.sm
        Layout.alignment: Qt.AlignVCenter

        // Recalibrate the turn-popup region.
        DofusRosterButton {
            icon: "\uf05b"   // crosshairs — pick the turn-popup region
            toggled: DofusSwap.calibrating
            tone: Theme.c.yellow
            tooltip: DofusSwap.calibrating
                ? "select the turn-popup region..."
                : "Recalibrate turn-popup region"
            screenName: root._screenName
            Layout.alignment: Qt.AlignVCenter
            onClicked: DofusSwap.calibrate()
        }

        // Start / stop the detector.
        DofusRosterButton {
            icon: DofusSwap.detectorRunning ? "\uf04d" : "\uf04b"   // stop / play
            toggled: true
            tone: DofusSwap.detectorRunning ? Theme.c.red : Theme.c.green
            tooltip: DofusSwap.detectorRunning
                ? "Stop swap detector"
                : "Start swap detector"
            screenName: root._screenName
            Layout.alignment: Qt.AlignVCenter
            onClicked: DofusSwap.toggle()
        }
    }
}
