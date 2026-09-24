// MoodPanel — the mode centre. What a mode actually controls (desktop-model.md):
// theme, active scenes and the monitor each lands on. The panel is a mode
// switcher plus a read-only view of the declaration's scene set for the
// active mode — notification policy, background task levels and launch
// aggression moved out of the per-mode surface (permissions/notification
// routing land in a later issue) since a mode never controlled them by the
// model, only enforced them as a historical accident of the old mood-policy
// shape. The one edit left is the palette lease, through Hyprfocus.patchMode.
// Opened from ModePill via PanelBus, same single-window pattern as CalendarPanel.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, PanelBus, Focus, Hyprfocus, SceneVeto
import "../../services/ModeExplain.js" as ModeExplain
import "../../services/ModeAnnounce.js" as ModeAnnounce
import "../common"        // Surface, PalettePicker, HoverDetail

Scope {
    id: scope

    // The active mode, re-read from Focus on every store change.
    readonly property string mood: Focus.mode
    // Hyprfocus.ids() already excludes hidden modes (neutral's recovery
    // fallback, reached only from the hypr modes submap) by the declaration's
    // own `hidden` flag - reuse it rather than re-deriving the same list from
    // the policy store's keys.
    readonly property var moodIds: Hyprfocus.ids().filter(id => Focus.policyData[id])

    // Cap so the panel fits on a laptop screen; taller content scrolls instead
    // of clipping (fs.xl = the largest type step, so the cap scales with the UI).
    // How much the panel can grow before it scrolls. Both knobs are steps on
    // the type scale rather than pixel counts, so the laptop lid and the
    // ultrawide compute their own answers (LEO-297): the mode list, per-task
    // cycling and the transitions all fit without scroll on the desktop and
    // get one x-height more on the lid before the scroll takes over.
    readonly property real maxCardHeight: Theme.fs.xl * 34
    readonly property real maxCardWidth: Theme.fs.xl * 26

    function adopt(id) { Focus.set(id, 0); closePanel(); }
    function stop() { Focus.stop(); closePanel(); }
    function closePanel() { PanelBus.close("mood"); }

    function untilLabel() {
        if (!Focus.until) return "";
        const ms = Date.parse(Focus.until) - Date.now();
        if (ms <= 0) return "";
        const m = Math.ceil(ms / 60000);
        return " · " + (m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m") + " left";
    }

    // The scene set the active mode declares, each with its monitor role and
    // the base catalog's icon (base.scenes[name].icon) — the panel's one data
    // source for "what runs where" is the declaration, never mood-policy.
    readonly property var scenePlacements: (Hyprfocus.current.scenes || []).map(p => ({
        name: p.name,
        monitor: p.monitor,
        icon: (Hyprfocus.data.base?.scenes?.[p.name]?.icon) || ""
    }))

    // The explain half (LEO-280): the declaration as sentences. The pointer's
    // provenance stands so the panel answers "why is my desk like this"
    // without reading a file by hand; the rows read the ACTIVE mode's own
    // record. Unknown-pointer states say so rather than showing nothing.
    readonly property string provenance: ModeExplain.provenance(
        { source: Hyprfocus.source, set_at: Hyprfocus.setAt }, Focus.until)
    readonly property var explained: Hyprfocus.known ? ModeExplain.rows(Hyprfocus.current) : []

    // The transition preview: what entering a chip would take, named before
    // the mode is entered (the announce model's own line, not a rewrite).
    // Rendered through HoverDetail so hovering a chip never resizes the card
    // (LEO-384) — the box exists whether this is "" or three lines long.
    property string _preview: ""
    function hoverChip(id) {
        const spec = Hyprfocus.modes[id];
        const a = spec ? ModeAnnounce.announce(spec, Hyprfocus.label(id)) : null;
        scope._preview = a ? a.body : "nothing taken away · enforces immediately";
    }

    // The palette-swatch hover preview (PalettePicker.onHoverName), same
    // reserved-space treatment as the mode preview above.
    property string _palettePreview: ""
    function hoverPalette(name) {
        const p = Theme.palettes[name];
        scope._palettePreview = p ? (name + " — base " + p.base + " · accent " + p.mauve) : "";
    }

    // Small uppercase section heading, same voice as the calendar panel.
    component SectionTag: Text {
        id: tag
        required property string title
        text: tag.title.toUpperCase()
        color: Theme.subtext
        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: Font.Bold }
    }

    PanelWindow {
        id: win
        visible: PanelBus.open === "mood"
        screen: PanelBus.screenObject(PanelBus.anchorScreen)
        color: "transparent"

        anchors { top: true; left: true; right: true }
        margins { top: Theme.barReserved + Theme.space.md }
        implicitHeight: card.implicitHeight

        WlrLayershell.layer: WlrLayer.Overlay
        // Frosted per this namespace in the hypr repo's layerrules.lua —
        // report: namespace "quickshell-mood", elevation "peek".
        WlrLayershell.namespace: "quickshell-mood"
        // OnDemand only while visible: a hidden PanelWindow still exists,
        // and Exclusive/OnDemand on an invisible layer surface can steal
        // focus from whatever's underneath.
        WlrLayershell.keyboardFocus: win.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusiveZone: 0
        mask: Region { item: card }

        Surface {
            id: card
            x: Math.max(Theme.space.sm, Math.min(PanelBus.anchorX - card.width / 2, win.width - card.width - Theme.space.sm))
            y: 0
            width: Math.min(scope.maxCardWidth, win.width - Theme.space.sm * 2)
            implicitHeight: Math.min(flick.contentHeight, scope.maxCardHeight) + Theme.space.xl * 2
            elevation: "peek"
            radius: Theme.radius

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: win.visible
                Keys.onEscapePressed: scope.closePanel()

                // Scroll when the whole policy outgrows the screen — the laptop
                // case — rather than clipping controls.
                Flickable {
                    id: flick
                    anchors { fill: parent; margins: Theme.space.lg }
                    contentHeight: content.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: content
                        width: flick.width
                        spacing: Theme.space.md

                        // -- header: which mood, how long left, and the way out.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.sm

                            Text {
                                Layout.fillWidth: true
                                // `work` is the default/resting mode: styled
                                // like the old neutral resting state, name and all —
                                // `neutral` itself is a hidden recovery mode, not this
                                // panel's idea of "at rest".
                                text: Focus.current.name + scope.untilLabel()
                                color: scope.mood === "work" ? Theme.subtext : Theme.accent
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.lg; weight: Font.Bold }
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                id: stopBtn
                                visible: scope.mood !== "work"
                                implicitWidth: stopLabel.implicitWidth + Theme.space.sm * 2
                                implicitHeight: stopLabel.implicitHeight + Theme.space.sm
                                radius: Theme.radiusSmall
                                color: Theme.withAlpha(Theme.error, 0.22)
                                border { width: 1; color: Theme.error }
                                Text {
                                    id: stopLabel
                                    anchors.centerIn: parent
                                    text: "stop"
                                    color: Theme.text
                                    font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                                }
                                MouseArea { anchors.fill: parent; onClicked: scope.stop() }
                            }
                        }

                        // -- mood picker: adopt any mood, open-ended.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.xs

                            Repeater {
                                model: scope.moodIds
                                delegate: Rectangle {
                                    id: chip
                                    required property string modelData
                                    readonly property bool active: chip.modelData === scope.mood
                                    readonly property string name: Focus.policyData[chip.modelData] ? Focus.policyData[chip.modelData].name : chip.modelData
                                    Layout.fillWidth: true
                                    implicitHeight: Theme.fs.sm + Theme.space.sm * 2 + 2
                                    radius: Theme.radiusSmall
                                    color: chip.active ? Theme.withAlpha(Theme.accent, 0.22) : Theme.withAlpha(Theme.surface, 0.5)
                                    border { width: 1; color: chip.active ? Theme.accent : Theme.withAlpha(Theme.border, 0.45) }
                                    Text {
                                        anchors.centerIn: parent
                                        text: chip.name
                                        color: chip.active ? Theme.accent : Theme.subtext
                                        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: chip.active ? Font.Bold : Font.Normal }
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onEntered: scope.hoverChip(chip.modelData)
                                        onExited: scope._preview = ""
                                        onClicked: scope.adopt(chip.modelData)
                                    }
                                }
                            }
                        }

                        // What entering the pointed-at chip takes, named before
                        // it is entered (LEO-280's read half) — reserved space
                        // (HoverDetail) so hovering a chip never resizes the card.
                        HoverDetail { text: scope._preview }
                        Text {
                            visible: (SceneVeto.last?.vetoes ?? []).length > 0
                            Layout.fillWidth: true
                            text: (SceneVeto.last?.vetoes ?? [])
                                .map(v => v.unit + " refused: " + (v.reason || "no reason")).join(" · ")
                            color: Theme.warning
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                        // -- scenes: the active mode's declared set, each on
                        // its monitor role (desktop-model.md: a mode controls
                        // theme, active scenes and monitor per scene — nothing
                        // else). Read-only: the declaration is edited by the
                        // CLI/seed, not this panel.
                        SectionTag { title: "scenes" }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.xs

                            Repeater {
                                model: scope.scenePlacements
                                delegate: RowLayout {
                                    id: srow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Theme.space.sm

                                    Text {
                                        text: srow.modelData.icon
                                        color: Theme.accent
                                        font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: srow.modelData.name
                                        color: Theme.text
                                        font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: srow.modelData.monitor
                                        color: Theme.subtext
                                        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                                    }
                                }
                            }
                        }
                        Text {
                            visible: scope.scenePlacements.length === 0
                            Layout.fillWidth: true
                            text: "no scenes declared for this mode"
                            color: Theme.subtextAlt
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                        // -- the declaration (LEO-280): the desk the compositor
                        // -- and every other runtime converge on, as sentences.
                        SectionTag { title: "the declaration" }

                        Text {
                            Layout.fillWidth: true
                            // `work` reads as any other pointer now \u2014 it is
                            // the resting default, not a special unpointed state the
                            // way `neutral` used to be.
                            text: "pointer: " + scope.mood + " \u00b7 " + scope.provenance
                            color: Theme.subtext
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.xs

                            Repeater {
                                model: scope.explained
                                delegate: RowLayout {
                                    id: explainRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Theme.space.md
                                    Text {
                                        Layout.preferredWidth: Theme.fs.xl * 5
                                        text: explainRow.modelData.label
                                        color: Theme.subtext
                                        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: explainRow.modelData.value
                                        color: Theme.text
                                        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                    }
                                }
                            }
                        }

                        // The palette lease is the one declared field the panel
                        // edits (LEO-280's edit half): validated before the
                        // write lands, live over the vocabulary every pack
                        // carries. Vacating the lease gives the desk back to
                        // the baseline with the same edit. A day/night pair
                        // (LEO-365) reads as "day / night" and has no single
                        // segment to highlight; picking a segment still writes
                        // a plain string, one palette for both halves.
                        //
                        // PalettePicker wraps into a swatch grid instead of one
                        // fixed row (LEO-384), so it stays readable regardless
                        // of how many palettes a pack ships.
                        SectionTag { title: "lease palette" }

                        PalettePicker {
                            id: palettePicker
                            readonly property var raw: (Hyprfocus.current.presentation || {}).palette
                            readonly property bool isPair: !!raw && typeof raw === "object"
                            Layout.fillWidth: true
                            entries: [{ name: "none", swatch: Theme.withAlpha(Theme.subtext, 0.3) }]
                                .concat(Object.keys(Theme.palettes).map(n => ({ name: n, swatch: Theme.palettes[n].base })))
                            value: palettePicker.isPair ? (palettePicker.raw.day + " / " + palettePicker.raw.night) : (palettePicker.raw || "none")
                            onHoverName: (name) => scope.hoverPalette(name)
                            onHoverEnd: () => scope._palettePreview = ""
                            onPick: (v) => {
                                const result = Hyprfocus.patchMode(scope.mood, { palette: v === "none" ? "" : v });
                                if (result !== "") {
                                    // Refused, not stored: a typo never becomes a desk
                                    // the compositor resolves into something else.
                                    Notify.send("edit refused", result, "error", true);
                                    return;
                                }
                                // Live on the external half too: the lease moved in
                                // place, so the same fan-out a mode entry owes runs.
                                Theme.noteLease();
                            }
                        }

                        // Swatch hover preview — reserved space, same as the
                        // mode-chip preview above.
                        HoverDetail { text: scope._palettePreview }

                        Text {
                            visible: !Hyprfocus.known
                            Layout.fillWidth: true
                            text: "the pointer names a mode the declaration does not carry \u2014 showing the policy, not a guess"
                            color: Theme.warning
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "edits apply to " + (scope.mood === "work" ? "the resting mode" : "\u201c" + Focus.current.name + "\u201d") + " \u00b7 persisted to hyprfocus.json"
                            color: Theme.subtextAlt
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }
                    }
                }
            }
        }
    }
}