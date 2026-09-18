// Control Centre — the one panel over Theme/Sound, both of which had a
// backend and no UI. Four sections: Theme (palette + day/night), Appearance
// (scale/transparency), Wallpaper, Sound.
//
// Mode switching moved out (LEO-366) — modules/bar/MoodPanel.qml owns modes
// (adopting one, stopping, the palette a mode leases); this panel never
// duplicates that. What is left here is what MoodPanel doesn't cover: the
// baseline palette/day-night pointer, per-palette wallpaper sets, and
// appearance/sound dials.
//
// Palette/day-night/scale/transparency are written straight to the `theme`
// Store (a second instance over the same theme.json Theme.qml reads — see
// services/Store.qml) rather than through Theme's IpcHandler, whose
// set/scale/transparency/cycle/auto functions are nested inside that
// IpcHandler and so aren't callable from outside it. The wallpaper section is
// the one exception: it never writes the store directly (decision: QML is
// never a wallpaper writer), it only calls Theme.wallpaperNext/Prev/Random/
// Pick, which shell out to `,theme.sh wallpaper ...` — see services/Theme.qml.
// Sound exposes its transport as plain functions on its own singleton, so
// that's called directly.
//
// The theme section renders AdapterResult (services/AdapterResult.qml), what
// `,theme.sh apply` actually did last time, rather than assuming the fan-out
// landed everywhere: see that file's header for why. Restart notices are
// rendered quiet and inline (small, subdued text) rather than as banners —
// a tier the user didn't ask about is context, not an alarm.
//
// The palette picker (both the theme grid and the wallpaper browser's target)
// and its hover preview reuse modules/common/PalettePicker.qml and
// HoverDetail.qml, shared with MoodPanel so both surfaces solve "many
// palettes" and "hover never resizes the panel" exactly once.
//
// Toggle from Hyprland:  qs -c quantumfate ipc call control toggle
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, AdapterResult, Sound, Focus, Store
import "../common"        // Surface
import "ControlLogic.js" as ControlLogic

Scope {
    id: scope

    property bool shown: false

    // The palette the pointer/browser is currently aimed at, distinct from
    // Theme.name (the palette actually applied). The wallpaper section below
    // binds to this — per-palette, not to the desk globally — so browsing
    // frappe's set shows and edits frappe's wallpaper, not whatever is live.
    property string previewPalette: Theme.name

    // Hover preview text for the theme swatch grid, rendered through
    // HoverDetail so hovering never resizes the panel (see PalettePicker.qml).
    property string _palettePreview: ""
    function hoverPalette(name) {
        const p = Theme.palettes[name];
        scope._palettePreview = p ? (name + " — base " + p.base + " · accent " + p.mauve) : "";
    }

    // Direct write access to the same file Theme.qml reads; see file header.
    Store {
        id: themeStore
        name: "theme"
    }

    IpcHandler {
        target: "control"
        function toggle(): void { scope.shown ? scope.hide() : scope.show(); }
        function show(): void { scope.show(); }
        function hide(): void { scope.hide(); }
    }

    function show() { Theme.wallpaperRefresh(scope.previewPalette); shown = true; }
    function hide() { shown = false; }
    onPreviewPaletteChanged: Theme.wallpaperRefresh(scope.previewPalette)

    // Fans a theme change out to kitty/GTK/Qt/wallpaper. Read `,theme.sh --help`
    // before touching this — `apply` is the only subcommand this panel needs,
    // since palette/wallpaper are already written to the store above and scale/
    // transparency are picked up live (transparency via the Hyprland reload the
    // script itself performs).
    Process { id: applier; command: [",theme.sh", "apply"] }
    function applyTheme() { applier.running = true; }

    function setPalette(name) {
        themeStore.set({ palette: name, mode: "manual" });
        scope.applyTheme();
    }
    function setMode(mode) { themeStore.set({ mode: mode }); }
    function setDay(name) { themeStore.set({ day: name }); }
    function setNight(name) { themeStore.set({ night: name }); }
    function setScale(value) { themeStore.set({ scale: ControlLogic.clamp(value, 0.8, 2.5) }); }
    function setTransparency(value) { themeStore.set({ transparency: ControlLogic.clamp(value, 0, 1) }); }

    readonly property var paletteNames: Object.keys(Theme.palettes)

    // Small reusable click-to-pick swatch used by the day/night pills. Kept
    // for those (a lighter footprint than the full PalettePicker fits their
    // inline row); the main theme grid below uses PalettePicker/HoverDetail.
    // day/night pills. `previewed` (keyboard/pointer focus) and `active`
    // (actually applied) are distinct so the picker can show both at once.
    component PalettePill: Rectangle {
        id: pill
        required property string paletteName
        property bool active: false
        property bool previewed: false
        signal picked()
        signal hovered()   // pointer parity for keyboard preview; day/night pills simply don't wire it

        readonly property var pal: Theme.palettes[pill.paletteName] ?? Theme.palettes.macchiato

        radius: Theme.radiusSmall
        color: Theme.withAlpha(pill.pal.base, 0.9)   // tokens-color-ok: this pill's own palette base, previewed on itself
        border {
            width: pill.active ? 2 : (pill.previewed ? 2 : 1)
            color: pill.active ? Theme.accent : (pill.previewed ? Theme.accentSecondary : Theme.withAlpha(Theme.border, 0.6))
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: pill.hovered()
            onClicked: pill.picked()
        }
    }

    // Six swatches lifted straight from the palette's own table: this is the
    // one legitimate place raw palette values are read for preview rather
    // than through a semantic role, since the point is to show what the
    // palette itself looks like.
    component SwatchStrip: RowLayout {
        id: strip
        required property var pal
        readonly property var keys: ["base", "surface0", "mauve", "teal", "peach", "red"]

        spacing: Theme.space.xs
        Repeater {
            model: strip.keys
            delegate: Rectangle {
                required property string modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: strip.pal[modelData] ?? strip.pal.mauve   // tokens-color-ok: swatch strip previews the palette's own raw colours
            }
        }
    }

    // A slider with no literal geometry: track height/handle size are steps on
    // Theme.space, and the fill fraction is purely value-driven.
    component DialSlider: Item {
        id: slider
        required property real value      // current, in [min, max]
        property real min: 0
        property real max: 1
        signal moved(real value)

        Layout.fillWidth: true
        implicitHeight: Theme.space.lg

        readonly property real fraction: ControlLogic.clamp((slider.value - slider.min) / (slider.max - slider.min), 0, 1)

        Rectangle {
            id: track
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            implicitHeight: Theme.space.sm
            radius: height / 2
            color: Theme.surface

            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: parent.width * slider.fraction
                radius: parent.radius
                color: Theme.accent
            }
        }

        Rectangle {
            id: handle
            y: (parent.height - height) / 2
            x: (track.width - width) * slider.fraction
            implicitWidth: Theme.space.lg
            implicitHeight: Theme.space.lg
            radius: width / 2
            color: Theme.accentAlt
            border { width: 1; color: Theme.withAlpha(Theme.border, 0.6) }
        }

        MouseArea {
            anchors.fill: parent
            onPositionChanged: (mouse) => {
                if (pressed) slider.moved(slider.min + ControlLogic.clamp(mouse.x / track.width, 0, 1) * (slider.max - slider.min));
            }
            onPressed: (mouse) => slider.moved(slider.min + ControlLogic.clamp(mouse.x / track.width, 0, 1) * (slider.max - slider.min))
        }
    }

    component SectionTitle: Text {
        color: Theme.accentAlt
        font { pixelSize: Theme.fs.sm; bold: true; letterSpacing: 1 }
    }

    PanelWindow {
        id: win
        visible: scope.shown
        screen: PanelBus.screenObject(PanelBus.activeScreen)
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        // Frosted per this namespace in the hypr repo's layerrules.lua —
        // report: namespace "quickshell-control", elevation "modal"
        // (alpha Theme.surfaceAlpha.modal = 0.97).
        WlrLayershell.namespace: "quickshell-control"

        onVisibleChanged: if (visible) focusScope.forceActiveFocus();

        // Click outside the card dismisses, but there is no dim backdrop.
        MouseArea { anchors.fill: parent; onClicked: scope.hide() }

        FocusScope {
            id: focusScope
            anchors.centerIn: parent
            width: card.width
            height: card.height
            Keys.onEscapePressed: scope.hide()

            Surface {
                id: card
                // Room in steps of the scale, not pixels: the mood widget's
                // transitions, per-task cycling and the wallpaper grid want
                // more than the half-screen slice the panel used to give, and
                // the laptop lid budgets its own fraction (LEO-297).
                width: Math.min(win.width * 0.62, Theme.fs.xl * 56)
                height: Math.min(win.height * 0.85, content.implicitHeight + 2 * Theme.pad)
                elevation: "modal"
                radius: Theme.radius

                Flickable {
                    anchors { fill: parent; margins: Theme.pad }
                    contentHeight: content.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: content
                        width: parent.width
                        spacing: Theme.gap

                        Text {
                            text: "Control Centre"
                            color: Theme.accent
                            font { pixelSize: Theme.fs.xl; bold: true }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }

                        // ---- Theme ----------------------------------------
                        SectionTitle { text: "THEME" }

                        // What applying will actually do, before it happens —
                        // the same nine-ish-surface fan-out regardless of which
                        // palette is picked, so this is honest to show up front.
                        Text {
                            text: AdapterResult.everRan
                                ? "Applying will reach: " + AdapterResult.tierSummary
                                : "Never applied yet on this machine"
                            color: Theme.subtextAlt
                            font.pixelSize: Theme.fs.xs
                        }

                        // Reused from the mode panel (modules/common/
                        // PalettePicker.qml): a fixed-footprint swatch chip
                        // that wraps instead of squeezing, so this stays
                        // readable at 4 palettes or 40. Clicking sets the
                        // active theme AND the wallpaper browser's target
                        // below; hovering only previews (HoverDetail, no
                        // resize).
                        PalettePicker {
                            id: themePicker
                            Layout.fillWidth: true
                            entries: scope.paletteNames.map(n => ({ name: n, swatch: Theme.palettes[n].base }))
                            value: scope.previewPalette
                            onHoverName: (name) => scope.hoverPalette(name)
                            onHoverEnd: () => scope._palettePreview = ""
                            onPick: (name) => {
                                scope.previewPalette = name;
                                scope.setPalette(name);
                            }
                        }
                        HoverDetail { text: scope._palettePreview }

                        // Quiet, inline restart notices — small and subdued
                        // rather than a banner: a tier the user didn't ask
                        // about is context, not an alarm. Each names the
                        // honest tier the last apply actually reported.
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: AdapterResult.pending.length > 0 || AdapterResult.failed.length > 0
                            spacing: Theme.space.xs

                            Repeater {
                                model: AdapterResult.pending
                                delegate: Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: modelData.surface + " — " + modelData.tier + ": " + modelData.reason
                                    color: Theme.subtextAlt
                                    font.pixelSize: Theme.fs.xs
                                }
                            }
                            Repeater {
                                model: AdapterResult.failed
                                delegate: Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: modelData.surface + " — " + modelData.reason
                                    color: Theme.error
                                    font.pixelSize: Theme.fs.xs
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.sm

                            Text { text: "Mode:"; color: Theme.subtext; font.pixelSize: Theme.fs.sm }
                            Repeater {
                                model: ["auto", "manual"]
                                delegate: Rectangle {
                                    id: modeBtn
                                    required property string modelData
                                    readonly property bool active: Theme.mode === modeBtn.modelData
                                    implicitWidth: modeText.implicitWidth + Theme.space.lg
                                    implicitHeight: modeText.implicitHeight + Theme.space.sm
                                    radius: Theme.radiusSmall
                                    color: modeBtn.active ? Theme.withAlpha(Theme.accent, 0.3) : Theme.surface
                                    border { width: 1; color: modeBtn.active ? Theme.accent : Theme.border }
                                    Text {
                                        id: modeText
                                        anchors.centerIn: parent
                                        text: modeBtn.modelData
                                        color: Theme.text
                                        font.pixelSize: Theme.fs.sm
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: scope.setMode(modeBtn.modelData) }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: Theme.mode === "auto"
                            spacing: Theme.space.md

                            ColumnLayout {
                                spacing: Theme.space.xs
                                Text { text: "Day"; color: Theme.subtext; font.pixelSize: Theme.fs.xs }
                                RowLayout {
                                    spacing: Theme.space.xs
                                    Repeater {
                                        model: scope.paletteNames
                                        delegate: PalettePill {
                                            id: dayPill
                                            required property string modelData
                                            Layout.preferredWidth: Theme.fs.lg
                                            Layout.preferredHeight: Theme.fs.lg
                                            paletteName: dayPill.modelData
                                            active: Theme.dayPalette === dayPill.modelData
                                            onPicked: scope.setDay(dayPill.modelData)
                                        }
                                    }
                                }
                            }
                            ColumnLayout {
                                spacing: Theme.space.xs
                                Text { text: "Night"; color: Theme.subtext; font.pixelSize: Theme.fs.xs }
                                RowLayout {
                                    spacing: Theme.space.xs
                                    Repeater {
                                        model: scope.paletteNames
                                        delegate: PalettePill {
                                            id: nightPill
                                            required property string modelData
                                            Layout.preferredWidth: Theme.fs.lg
                                            Layout.preferredHeight: Theme.fs.lg
                                            paletteName: nightPill.modelData
                                            active: Theme.nightPalette === nightPill.modelData
                                            onPicked: scope.setNight(nightPill.modelData)
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                        // ---- Appearance ------------------------------------
                        SectionTitle { text: "APPEARANCE" }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.md
                            Text { Layout.preferredWidth: Theme.fs.xl * 4; text: "Scale"; color: Theme.text; font.pixelSize: Theme.fs.sm }
                            DialSlider {
                                Layout.fillWidth: true
                                min: 0.8; max: 2.5
                                value: Theme.scale
                                onMoved: (v) => scope.setScale(v)
                            }
                            Text {
                                Layout.preferredWidth: Theme.fs.xl * 2
                                text: Theme.scale.toFixed(2)
                                color: Theme.subtext
                                font.pixelSize: Theme.fs.sm
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.md
                            Text { Layout.preferredWidth: Theme.fs.xl * 4; text: "Transparency"; color: Theme.text; font.pixelSize: Theme.fs.sm }
                            DialSlider {
                                Layout.fillWidth: true
                                min: 0; max: 1
                                value: Theme.transparency
                                onMoved: (v) => scope.setTransparency(v)
                            }
                            Text {
                                Layout.preferredWidth: Theme.fs.xl * 2
                                text: Theme.transparency.toFixed(2)
                                color: Theme.subtext
                                font.pixelSize: Theme.fs.sm
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                        // ---- Wallpaper -------------------------------------
                        // A per-monitor browser for the previewed palette's
                        // set (LEO-366), not a cramped grid: one row per
                        // monitor showing what it currently has, with
                        // next/prev stepping it live through the shuffled
                        // set. Every mutation calls Theme.wallpaperNext/Prev/
                        // Pick, which shell out to `,theme.sh wallpaper ...`
                        // — this panel never writes the wallpaper store
                        // itself (see services/Theme.qml's header).
                        SectionTitle { text: "WALLPAPER — " + scope.previewPalette }

                        readonly property var wallpaperMonitors: Object.keys(Theme.wallpaperSet.monitors ?? ({}))

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.sm

                            Repeater {
                                model: content.wallpaperMonitors
                                delegate: RowLayout {
                                    id: monRow
                                    required property string modelData
                                    readonly property var pick: Theme.wallpaperSet.monitors[monRow.modelData] ?? ({})
                                    // "*" is the one-wallpaper-for-everything
                                    // surface name ,theme.sh records applied/
                                    // pending/failed under (see apply_wallpaper
                                    // in bin/,theme.sh); a real output name
                                    // gets its own "wallpaper[NAME]" surface.
                                    readonly property string surface: monRow.modelData === "*" ? "wallpaper" : "wallpaper[" + monRow.modelData + "]"
                                    readonly property string tier: AdapterResult.tierFor(monRow.surface)
                                    Layout.fillWidth: true
                                    spacing: Theme.space.sm

                                    Rectangle {
                                        Layout.preferredWidth: Theme.fs.xl * 4
                                        Layout.preferredHeight: Theme.fs.xl * 2.4
                                        radius: Theme.radiusSmall
                                        color: Theme.surface
                                        border { width: 1; color: Theme.border }
                                        clip: true
                                        Image {
                                            anchors.fill: parent
                                            source: monRow.pick.current ? "file://" + Theme.wallpaperRoot + "/" + monRow.pick.current : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            visible: status === Image.Ready
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.space.xs
                                        Text {
                                            text: monRow.modelData === "*" ? "all monitors" : monRow.modelData
                                            color: Theme.text
                                            font.pixelSize: Theme.fs.sm
                                        }
                                        Text {
                                            text: monRow.pick.current ? monRow.pick.current.split("/").pop() : "none bound"
                                            color: Theme.subtext
                                            font.pixelSize: Theme.fs.xs
                                            elide: Text.ElideMiddle
                                        }
                                        // Quiet, inline — the honest tier from
                                        // the last apply, not shown at all
                                        // when it's the unremarkable case
                                        // (already immediate).
                                        Text {
                                            visible: monRow.tier !== "" && monRow.tier !== "immediate"
                                            text: monRow.tier
                                            color: Theme.subtextAlt
                                            font.pixelSize: Theme.fs.xs
                                        }
                                    }

                                    Rectangle {
                                        implicitWidth: prevLabel.implicitWidth + Theme.space.lg
                                        implicitHeight: prevLabel.implicitHeight + Theme.space.sm
                                        radius: Theme.radiusSmall
                                        color: Theme.surface
                                        border { width: 1; color: Theme.border }
                                        Text { id: prevLabel; anchors.centerIn: parent; text: "prev"; color: Theme.text; font.pixelSize: Theme.fs.sm }
                                        MouseArea { anchors.fill: parent; onClicked: Theme.wallpaperPrev(scope.previewPalette, monRow.modelData) }
                                    }
                                    Rectangle {
                                        implicitWidth: nextLabel.implicitWidth + Theme.space.lg
                                        implicitHeight: nextLabel.implicitHeight + Theme.space.sm
                                        radius: Theme.radiusSmall
                                        color: Theme.surface
                                        border { width: 1; color: Theme.border }
                                        Text { id: nextLabel; anchors.centerIn: parent; text: "next"; color: Theme.text; font.pixelSize: Theme.fs.sm }
                                        MouseArea { anchors.fill: parent; onClicked: Theme.wallpaperNext(scope.previewPalette, monRow.modelData) }
                                    }
                                }
                            }

                            Text {
                                visible: content.wallpaperMonitors.length === 0
                                Layout.fillWidth: true
                                text: "no monitors reported yet for " + scope.previewPalette
                                color: Theme.subtext
                                font.pixelSize: Theme.fs.sm
                            }
                        }

                        // Full-size review + pick: opens the whole set in feh
                        // (decision 6 — previewing there is live too, through
                        // the same script; see Theme.openWallpaperViewer).
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.sm
                            Text {
                                Layout.fillWidth: true
                                text: Theme.wallpaperSet.count + " wallpapers in " + scope.previewPalette + "’s set"
                                color: Theme.subtextAlt
                                font.pixelSize: Theme.fs.xs
                            }
                            Rectangle {
                                implicitWidth: browseLabel.implicitWidth + Theme.space.lg
                                implicitHeight: browseLabel.implicitHeight + Theme.space.sm
                                radius: Theme.radiusSmall
                                color: Theme.withAlpha(Theme.accent, 0.18)
                                border { width: 1; color: Theme.accent }
                                Text { id: browseLabel; anchors.centerIn: parent; text: "browse in feh"; color: Theme.accent; font.pixelSize: Theme.fs.sm }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Theme.openWallpaperViewer(scope.previewPalette, win.screen.width, win.screen.height)
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                        // ---- Sound ------------------------------------------
                        SectionTitle { text: "SOUND" }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.sm
                            Repeater {
                                model: ["rain", "lofi", "off"]
                                delegate: Rectangle {
                                    id: soundBtn
                                    required property string modelData
                                    readonly property bool active: Sound.mode === soundBtn.modelData
                                    implicitWidth: soundText.implicitWidth + Theme.space.lg
                                    implicitHeight: soundText.implicitHeight + Theme.space.sm
                                    radius: Theme.radiusSmall
                                    color: soundBtn.active ? Theme.withAlpha(Theme.accent, 0.3) : Theme.surface
                                    border { width: 1; color: soundBtn.active ? Theme.accent : Theme.border }
                                    Text {
                                        id: soundText
                                        anchors.centerIn: parent
                                        text: soundBtn.modelData
                                        color: Theme.text
                                        font.pixelSize: Theme.fs.sm
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: soundBtn.modelData === "off" ? Sound.stop() : Sound.play(soundBtn.modelData)
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Sound.mode === "off" ? "stopped" : (Sound.track ? Sound.track.split("/").pop() : "")
                                color: Theme.subtext
                                font.pixelSize: Theme.fs.xs
                                elide: Text.ElideMiddle
                                Layout.preferredWidth: Theme.fs.xl * 6
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.md
                            Text { Layout.preferredWidth: Theme.fs.xl * 4; text: "Volume"; color: Theme.text; font.pixelSize: Theme.fs.sm }
                            DialSlider {
                                Layout.fillWidth: true
                                min: 0; max: 1
                                value: Sound.volume
                                onMoved: (v) => Sound.setVolume(v)
                            }
                            Text {
                                Layout.preferredWidth: Theme.fs.xl * 2
                                text: Sound.volume.toFixed(2)
                                color: Theme.subtext
                                font.pixelSize: Theme.fs.sm
                            }
                        }
                    }
                }
            }
        }
    }
}
