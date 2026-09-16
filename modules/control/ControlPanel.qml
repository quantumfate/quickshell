// Control Centre — the one panel over Theme/Sound/Focus, all of which had a
// backend and no UI. Five sections: Theme (palette + day/night), Appearance
// (scale/transparency), Wallpaper, Sound, Focus.
//
// Palette/day-night/scale/transparency/wallpaper are written straight to the
// `theme` Store (a second instance over the same theme.json Theme.qml reads —
// see services/Store.qml) rather than through Theme's IpcHandler, whose
// set/scale/transparency/cycle/auto functions are nested inside that
// IpcHandler and so aren't callable from outside it. Sound and Focus expose
// their transport as plain functions on the singleton itself, so those are
// called directly.
//
// The theme section renders AdapterResult (services/AdapterResult.qml), what
// `,theme.sh apply` actually did last time, rather than assuming the fan-out
// landed everywhere: see that file's header for why.
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
    property var wallpapers: []   // filenames under ~/.config/hypr/wallpapers

    // The palette the keyboard/pointer is currently pointed at, distinct from
    // Theme.name (the palette actually applied). The wallpaper picker below
    // binds to this — per-palette, not to the desk globally — so previewing
    // frappe shows and edits frappe's wallpaper, not whatever is live.
    property string previewPalette: Theme.name
    property int previewIndex: Math.max(0, Object.keys(Theme.palettes).indexOf(Theme.name))

    readonly property string wallpaperDir: Quickshell.env("HOME") + "/.config/hypr/wallpapers"

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

    function show() { wallpaperLister.running = true; shown = true; }
    function hide() { shown = false; }

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

    // Binds a wallpaper to whichever palette is previewed, not to the desk
    // globally — Theme.wallpapers is a palette -> filename map, and this
    // panel is the only writer of it.
    function setWallpaper(name) {
        const map = Object.assign({}, Theme.wallpapers);
        map[scope.previewPalette] = name;
        themeStore.set({ wallpapers: map });
        if (scope.previewPalette === Theme.name) scope.applyTheme();
    }

    // Moves the preview cursor by name (pointer) or by grid step (keyboard);
    // both funnel through here so previewIndex and previewPalette never drift
    // apart.
    readonly property var paletteNames: Object.keys(Theme.palettes)
    function previewByName(name) {
        const i = scope.paletteNames.indexOf(name);
        if (i >= 0) { scope.previewIndex = i; scope.previewPalette = name; }
    }
    function previewMove(key) {
        scope.previewIndex = ControlLogic.moveGridIndex(scope.previewIndex, key, scope.paletteNames.length, 4);
        scope.previewPalette = scope.paletteNames[scope.previewIndex];
    }

    Process {
        id: wallpaperLister
        command: ["bash", "-lc", "ls -1 '" + scope.wallpaperDir + "' 2>&1"]
        stdout: StdioCollector {
            onStreamFinished: scope.wallpapers = ControlLogic.parseWallpaperList(text)
        }
    }

    // Small reusable click-to-pick swatch used by both the palette grid and the
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
            Keys.onPressed: (event) => {
                const key = { [Qt.Key_H]: "h", [Qt.Key_J]: "j", [Qt.Key_K]: "k", [Qt.Key_L]: "l" }[event.key];
                if (key) { scope.previewMove(key); event.accepted = true; }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    scope.setPalette(scope.previewPalette);
                    event.accepted = true;
                }
            }

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

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            rowSpacing: Theme.space.sm
                            columnSpacing: Theme.space.sm

                            Repeater {
                                model: scope.paletteNames
                                delegate: PalettePill {
                                    id: swatch
                                    required property string modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.fs.xl * 2.8
                                    paletteName: swatch.modelData
                                    active: Theme.name === swatch.modelData
                                    previewed: scope.previewPalette === swatch.modelData
                                    onPicked: scope.setPalette(swatch.modelData)
                                    onHovered: scope.previewByName(swatch.modelData)

                                    ColumnLayout {
                                        anchors { fill: parent; margins: Theme.space.xs }
                                        spacing: Theme.space.xs
                                        SwatchStrip { Layout.fillWidth: true; Layout.fillHeight: true; pal: swatch.pal }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: swatch.paletteName
                                            color: swatch.pal.text
                                            font { pixelSize: Theme.fs.xs; bold: swatch.active }
                                        }
                                    }
                                }
                            }
                        }

                        // The quiet chip: only what is still outstanding, named
                        // with its reason, so "restart Zen" is actionable.
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
                                    text: "restart required — " + modelData.surface + ": " + modelData.reason
                                    color: Theme.pending
                                    font.pixelSize: Theme.fs.xs
                                }
                            }
                            Repeater {
                                model: AdapterResult.failed
                                delegate: Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: "failed — " + modelData.surface + ": " + modelData.reason
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
                        // Bound to the previewed palette, not the desk: picking
                        // one here writes Theme.wallpapers[previewPalette].
                        SectionTitle { text: "WALLPAPER — " + scope.previewPalette }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            rowSpacing: Theme.space.sm
                            columnSpacing: Theme.space.sm

                            Repeater {
                                model: scope.wallpapers
                                delegate: Rectangle {
                                    id: wp
                                    required property string modelData
                                    readonly property bool active: Theme.wallpaperFor(scope.previewPalette) === wp.modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.fs.xl * 3
                                    radius: Theme.radiusSmall
                                    color: Theme.surface
                                    border { width: wp.active ? 2 : 1; color: wp.active ? Theme.accent : Theme.border }
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: "file://" + scope.wallpaperDir + "/" + wp.modelData
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        visible: status === Image.Ready
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: parent.children[0].status !== Image.Ready
                                        text: wp.modelData
                                        color: Theme.subtext
                                        font.pixelSize: Theme.fs.xs
                                        wrapMode: Text.Wrap
                                        width: parent.width - Theme.space.sm
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: scope.setWallpaper(wp.modelData) }
                                }
                            }
                        }
                        Text {
                            visible: scope.wallpapers.length === 0
                            text: "No wallpapers found in " + scope.wallpaperDir
                            color: Theme.subtext
                            font.pixelSize: Theme.fs.sm
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

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                        // ---- Focus ------------------------------------------
                        SectionTitle { text: "FOCUS" }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.sm

                            Rectangle {
                                implicitWidth: startText.implicitWidth + Theme.space.lg
                                implicitHeight: startText.implicitHeight + Theme.space.sm
                                radius: Theme.radiusSmall
                                color: Focus.active ? Theme.surface : Theme.withAlpha(Theme.success, 0.3)
                                border { width: 1; color: Focus.active ? Theme.border : Theme.success }
                                Text {
                                    id: startText
                                    anchors.centerIn: parent
                                    text: "Start"
                                    color: Theme.text
                                    font.pixelSize: Theme.fs.sm
                                }
                                MouseArea { anchors.fill: parent; onClicked: Focus.set("work", 0) }
                            }
                            Rectangle {
                                implicitWidth: stopText.implicitWidth + Theme.space.lg
                                implicitHeight: stopText.implicitHeight + Theme.space.sm
                                radius: Theme.radiusSmall
                                color: Focus.active ? Theme.withAlpha(Theme.error, 0.3) : Theme.surface
                                border { width: 1; color: Focus.active ? Theme.error : Theme.border }
                                Text {
                                    id: stopText
                                    anchors.centerIn: parent
                                    text: "Stop"
                                    color: Theme.text
                                    font.pixelSize: Theme.fs.sm
                                }
                                MouseArea { anchors.fill: parent; onClicked: Focus.stop() }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Focus.active ? ("focus — " + (Focus.until ? ("until " + Focus.until) : "no limit")) : "off"
                                color: Theme.subtext
                                font.pixelSize: Theme.fs.xs
                            }
                        }
                    }
                }
            }
        }
    }
}
