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
// Responsiveness is part of the contract here. Every dial follows the pointer
// while it is dragged (DialSlider tracks its own `_drag`) and commits its value
// through a short debounce, because a scale write relayouts the whole shell and
// a volume write forks a process. The wallpaper browser reads each monitor's
// live pick straight from the `wallpapers` key `,theme.sh` writes — which the
// store already watches — instead of its own ~1s `wallpaper list`, and the
// mutations are queued in Theme.qml so two quick arrow presses each count
// rather than the second overwriting the one in flight.
//
// The SYSTEM section at the top reads services/SysStats.qml — the same
// sampler the bar cluster and SysPanel read, so the machine is described in
// one place and this panel adds no second polling path. It is here because
// the control centre is where the desk is inspected and adjusted; the bar
// popout stays the glanceable version of the same numbers.
//
// Toggle from Hyprland:  qs -c quantumfate ipc call -- control toggle
// (the `--` matters: `show`/`hide` collide with `qs ipc` subcommand names)
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

    // Dial writes are debounced. A scale write relayouts every surface in the
    // shell, and a volume write forks a process to talk to mpv; firing one per
    // mouse-move is what made the dials feel like they were fighting the
    // pointer. The dial itself still follows the pointer regardless
    // (DialSlider tracks `_drag` while pressed), so nothing visible waits here.
    Timer {
        id: scaleDebounce; interval: 80; repeat: false
        property real v: 1
        onTriggered: scope.setScale(scaleDebounce.v)
    }
    Timer {
        id: transparencyDebounce; interval: 80; repeat: false
        property real v: 1
        onTriggered: scope.setTransparency(transparencyDebounce.v)
    }
    Timer {
        id: volumeDebounce; interval: 80; repeat: false
        property real v: 0.5
        onTriggered: Sound.setVolume(volumeDebounce.v)
    }

    // The live wallpaper pick for one output, straight from the `wallpapers`
    // key `,theme.sh` writes to theme.json — which the store already watches.
    // The browser used to show `wallpaper list`'s snapshot instead, and that
    // list costs about a second, so every arrow press sat behind it. The script
    // remains the only writer; this only reads back what it wrote. The value is
    // either `{output: "palette/file"}` (multi-monitor) or a bare "palette/file".
    function currentFor(palette, output) {
        const w = Theme.wallpapers?.[palette];
        if (w && typeof w === "object") return w[output] ?? w["*"] ?? "";
        return typeof w === "string" ? w : "";
    }

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

        // While the pointer is down the handle follows the cursor exactly; the
        // caller's `value` only takes over again on release. Binding the handle
        // straight to `value` made it trail a store round-trip behind the
        // pointer — the "wonky" the dials were accused of.
        property real _drag: 0
        readonly property real shown: area.pressed ? slider._drag : slider.value
        readonly property real fraction: ControlLogic.clamp((slider.shown - slider.min) / (slider.max - slider.min), 0, 1)

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
            id: area
            anchors.fill: parent
            function valueAt(x) {
                return slider.min + ControlLogic.clamp(x / track.width, 0, 1) * (slider.max - slider.min);
            }
            onPressed: (mouse) => { slider._drag = valueAt(mouse.x); slider.moved(slider._drag); }
            onPositionChanged: (mouse) => {
                if (!pressed) return;
                slider._drag = valueAt(mouse.x);
                slider.moved(slider._drag);
            }
        }
    }

    // One machine reading: a label, the number, a meter, and a quiet line of
    // detail. Fixed footprint so the grid stays a grid while the numbers
    // change width underneath it -- a tile that resizes per sample makes the
    // whole panel twitch once a second.
    component StatTile: Rectangle {
        id: tile
        required property string label
        required property string value
        property string detail: ""
        property real ratio: -1          // < 0 means "no meter, just numbers"
        property color tint: Theme.accent

        implicitHeight: tileBody.implicitHeight + Theme.space.md * 2
        radius: Theme.radiusSmall
        color: Theme.withAlpha(Theme.surface, 0.6)
        border { width: 1; color: Theme.withAlpha(Theme.border, 0.5) }

        ColumnLayout {
            id: tileBody
            anchors { fill: parent; margins: Theme.space.md }
            spacing: Theme.space.xs

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: tile.label
                    color: Theme.subtextAlt
                    font { pixelSize: Theme.fs.xs; letterSpacing: 1 }
                    elide: Text.ElideRight
                }
                Text {
                    text: tile.value
                    color: Theme.text
                    font { pixelSize: Theme.fs.md; bold: true }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: tile.ratio >= 0
                implicitHeight: Theme.space.xs
                radius: height / 2
                color: Theme.withAlpha(Theme.border, 0.5)
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * ControlLogic.clamp(tile.ratio, 0, 1)
                    radius: parent.radius
                    color: tile.tint
                }
            }

            Text {
                Layout.fillWidth: true
                visible: tile.detail !== ""
                text: tile.detail
                color: Theme.subtext
                font.pixelSize: Theme.fs.xs
                elide: Text.ElideRight
            }
        }
    }

    component SectionTitle: Text {
        color: Theme.accentAlt
        font { pixelSize: Theme.fs.sm; bold: true; letterSpacing: 1 }
    }

    // One wallpaper-browser arrow. Hover and press are visible so a click reads
    // as registered the instant it lands; the mutation behind it is a script
    // round-trip, and the queue in Theme.qml is what makes repeated clicks each
    // count instead of overwriting the one in flight.
    component StepButton: Rectangle {
        id: step
        required property string label
        signal stepped()

        implicitWidth: stepLabel.implicitWidth + Theme.space.lg
        implicitHeight: stepLabel.implicitHeight + Theme.space.sm
        radius: Theme.radiusSmall
        color: area.pressed ? Theme.withAlpha(Theme.accent, 0.3)
             : area.containsMouse ? Theme.surfaceAlt
             : Theme.surface
        border { width: 1; color: area.containsMouse ? Theme.accent : Theme.border }

        Text {
            id: stepLabel
            anchors.centerIn: parent
            text: step.label
            color: Theme.text
            font.pixelSize: Theme.fs.sm
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: step.stepped()
        }
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

        readonly property string _screenName: win.screen?.name ?? ""
        // Placed in the scene's published work area (docs/scenes.md
        // "Areas"): same width ratio the panel always used against the
        // whole screen (services/SurfaceDefaults.js "control"), now capped
        // against the area so it can never sit under a bar.
        readonly property var _box: PanelBus.surfaceBox(win._screenName, "control", { width: Theme.fs.xl * 72, height: content.implicitHeight + 2 * Theme.pad })

        FocusScope {
            id: focusScope
            x: win._box.x
            y: win._box.y
            width: win._box.width
            height: win._box.height
            Keys.onEscapePressed: scope.hide()

            Surface {
                id: card
                anchors.fill: parent
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

                        // ---- System ---------------------------------------
                        // Read-only: this is what the machine is doing, not a
                        // dial. Every value comes from SysStats, which samples
                        // /proc directly for the fast ones and shells out on a
                        // slower cadence for disk and GPU.
                        SectionTitle { text: "SYSTEM" }

                        GridLayout {
                            Layout.fillWidth: true
                            // Three across on the ultrawide, one on the lid:
                            // the column count follows the card, so no width
                            // has a row of slivers.
                            columns: Math.max(1, Math.floor(card.width / (Theme.fs.xl * 16)))
                            columnSpacing: Theme.space.sm
                            rowSpacing: Theme.space.sm

                            StatTile {
                                Layout.fillWidth: true
                                label: "CPU"
                                tint: Theme.c.lavender
                                value: SysStats.cpuPct + "%"
                                ratio: SysStats.cpuPct / 100
                                detail: SysStats.cpuCores + " cores · load " + SysStats.loadAvg
                            }
                            StatTile {
                                Layout.fillWidth: true
                                label: "MEMORY"
                                tint: Theme.c.green
                                value: SysStats.memPct + "%"
                                ratio: SysStats.memPct / 100
                                detail: SysStats.memUsedG.toFixed(1) + " / " + SysStats.memTotalG.toFixed(1) + " G"
                            }
                            StatTile {
                                Layout.fillWidth: true
                                label: "SWAP"
                                tint: Theme.c.peach
                                visible: SysStats.swapTotalG > 0
                                value: SysStats.swapTotalG > 0
                                    ? Math.round(100 * SysStats.swapUsedG / SysStats.swapTotalG) + "%" : "—"
                                ratio: SysStats.swapTotalG > 0 ? SysStats.swapUsedG / SysStats.swapTotalG : 0
                                detail: SysStats.swapUsedG.toFixed(1) + " / " + SysStats.swapTotalG.toFixed(1) + " G"
                            }
                            // Absent on a machine with no NVIDIA card: the
                            // tile is not a placeholder for hardware that is
                            // not there (SysStats.gpuPresent).
                            StatTile {
                                Layout.fillWidth: true
                                label: "GPU"
                                tint: Theme.c.teal
                                visible: SysStats.gpuPresent
                                value: SysStats.gpuPct + "%"
                                ratio: SysStats.gpuPct / 100
                                detail: SysStats.gpuTemp + "°C · " + SysStats.gpuMemUsedG.toFixed(1)
                                    + " / " + SysStats.gpuMemTotalG.toFixed(1) + " G"
                            }
                            StatTile {
                                Layout.fillWidth: true
                                label: "DISK /"
                                tint: Theme.c.sapphire
                                value: SysStats.diskUsedPct
                                ratio: (parseInt(SysStats.diskUsedPct) || 0) / 100
                                detail: SysStats.diskFree + " free"
                            }
                            StatTile {
                                Layout.fillWidth: true
                                label: SysStats.wifiSignal >= 0 ? "WI-FI" : "NETWORK"
                                tint: Theme.c.sky
                                value: SysStats.wifiSsid || SysStats.netState
                                detail: "↓ " + SysStats.fmtRate(SysStats.rxRate)
                                    + "   ↑ " + SysStats.fmtRate(SysStats.txRate)
                                    + (SysStats.wifiSignal >= 0 ? "   " + SysStats.wifiSignal + "%" : "")
                            }
                            StatTile {
                                Layout.fillWidth: true
                                label: "UPTIME"
                                tint: Theme.c.mauve
                                value: SysStats.uptime
                                detail: SysStats.netIface
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

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
                                    color: modeBtn.active ? Theme.withAlpha(Theme.accent, 0.3)
                                        : modeHover.hovered ? Theme.surfaceAlt : Theme.surface
                                    border { width: 1; color: modeBtn.active ? Theme.accent : Theme.border }
                                    Text {
                                        id: modeText
                                        anchors.centerIn: parent
                                        text: modeBtn.modelData
                                        color: Theme.text
                                        font.pixelSize: Theme.fs.sm
                                    }
                                    HoverHandler { id: modeHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: scope.setMode(modeBtn.modelData)
                                    }
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
                                onMoved: (v) => { scaleDebounce.v = v; scaleDebounce.restart(); }
                            }
                            Text {
                                Layout.preferredWidth: Theme.fs.xl * 2
                                text: (scaleDebounce.running ? scaleDebounce.v : Theme.scale).toFixed(2)
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
                                onMoved: (v) => { transparencyDebounce.v = v; transparencyDebounce.restart(); }
                            }
                            Text {
                                Layout.preferredWidth: Theme.fs.xl * 2
                                text: (transparencyDebounce.running ? transparencyDebounce.v : Theme.transparency).toFixed(2)
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
                                    // What this output is showing RIGHT NOW, from
                                    // the store the script writes — not from the
                                    // `wallpaper list` snapshot, which is a
                                    // second behind. `pick.current` remains the
                                    // fallback for the first paint, before the
                                    // list has answered at all.
                                    readonly property string current: scope.currentFor(scope.previewPalette, monRow.modelData) || (monRow.pick.current ?? "")
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
                                            source: monRow.current ? "file://" + Theme.wallpaperRoot + "/" + monRow.current : ""
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
                                            text: monRow.current ? monRow.current.split("/").pop() : "none bound"
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

                                    RowLayout {
                                        spacing: Theme.space.xs
                                        Text { text: "Blur"; color: Theme.subtext; font.pixelSize: Theme.fs.xs }
                                        DialSlider {
                                            Layout.preferredWidth: Theme.fs.xl * 5
                                            min: 0; max: 48
                                            value: Theme.blurForOutput(monRow.modelData)
                                            onMoved: (v) => {
                                                blurDebounce.targetValue = Math.round(v);
                                                blurDebounce.restart();
                                            }
                                        }
                                        Text {
                                            Layout.preferredWidth: Theme.fs.xl * 2
                                            text: {
                                                const b = blurDebounce.running ? blurDebounce.targetValue : Theme.blurForOutput(monRow.modelData);
                                                return b === 0 ? "off" : b.toString();
                                            }
                                            color: Theme.subtext
                                            font.pixelSize: Theme.fs.xs
                                        }
                                        Timer {
                                            id: blurDebounce
                                            interval: 200
                                            repeat: false
                                            property int targetValue: 18
                                            onTriggered: Theme.setWallpaperBlur(scope.previewPalette, monRow.modelData, targetValue)
                                        }
                                    }

                                    StepButton {
                                        label: "prev"
                                        onStepped: Theme.wallpaperPrev(scope.previewPalette, monRow.modelData)
                                    }
                                    StepButton {
                                        label: "next"
                                        onStepped: Theme.wallpaperNext(scope.previewPalette, monRow.modelData)
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
                                    // Shrunk below the raw screen size so feh's own
                                    // scale-down math already targets roughly the
                                    // frame the hypr-side windowrule will enforce
                                    // (monitor minus default_gaps) rather than the
                                    // full monitor — see Theme.openWallpaperViewer.
                                    onClicked: Theme.openWallpaperViewer(scope.previewPalette, win.screen.width * 0.8, win.screen.height * 0.8)
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
                                    color: soundBtn.active ? Theme.withAlpha(Theme.accent, 0.3)
                                        : soundHover.hovered ? Theme.surfaceAlt : Theme.surface
                                    border { width: 1; color: soundBtn.active ? Theme.accent : Theme.border }
                                    Text {
                                        id: soundText
                                        anchors.centerIn: parent
                                        text: soundBtn.modelData
                                        color: Theme.text
                                        font.pixelSize: Theme.fs.sm
                                    }
                                    HoverHandler { id: soundHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
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
                                onMoved: (v) => { volumeDebounce.v = v; volumeDebounce.restart(); }
                            }
                            Text {
                                Layout.preferredWidth: Theme.fs.xl * 2
                                text: (volumeDebounce.running ? volumeDebounce.v : Sound.volume).toFixed(2)
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
