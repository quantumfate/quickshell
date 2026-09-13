pragma Singleton
// Central theme. One place every widget reads colors from, so a future
// "reload my whole theme" is a single palette switch here (and eventually the
// seam to unify Hyprland/GTK/etc. theming under Quickshell).
//
// The active palette name is backed by a Store ($XDG_STATE_HOME/theme.json),
// so it can be changed live from anywhere and every binding reacts:
//   qs -c quantumfate ipc call theme set mocha    (once more palettes exist)
//   or just edit theme.json -> { "palette": "frappe" }
import Quickshell
import Quickshell.Io
import QtQuick
import "."

Singleton {
    id: root

    Store {
        id: store
        name: "theme"
        // The full contract. Everything that decides how the desk looks lives
        // here, so "one button" is one `store.set` and any surface that cannot
        // watch a JSON file is reached by `,theme.sh apply` reading the same
        // fields.
        defaults: ({
            palette: "macchiato",   // the active palette
            mode: "auto",           // "auto" follows the sun, "manual" pins `palette`
            day: "latte",
            night: "macchiato",
            scale: 1.25,            // UI scale; see `fs` and `space` below
            opacity: 1.0,           // global window-opacity dial (1 = opaque)
            wallpaper: "",          // "" = the palette's default, resolved by ,theme.sh
            cheatsheet_linger_ms: 400
        })
    }

    readonly property string name: store.get("palette") ?? "macchiato"

    // How the palette is chosen. "auto" hands the decision to the sun timer;
    // "manual" means a deliberate pick that outlasts the next sunrise.
    readonly property string mode: store.get("mode") ?? "auto"
    readonly property string dayPalette: store.get("day") ?? "latte"
    readonly property string nightPalette: store.get("night") ?? "macchiato"

    // Read by the Hyprland opacity rules rather than by the shell itself: one
    // dial over the whole role table, and 1.0 is a hard "everything opaque".
    readonly property real opacity: store.get("opacity") ?? 1.0

    // "" means the palette decides; `,theme.sh` resolves and applies it.
    readonly property string wallpaper: store.get("wallpaper") ?? ""

    // Raw palettes. Add more here; switching is just a name change. `cycle`
    // walks them in insertion order.
    readonly property var palettes: ({
        frappe: {
            rosewater: "#f2d5cf", flamingo: "#eebebe", pink: "#f4b8e4", mauve: "#ca9ee6",
            red: "#e78284", maroon: "#ea999c", peach: "#ef9f76", yellow: "#e5c890",
            green: "#a6d189", teal: "#81c8be", sky: "#99d1db", sapphire: "#85c1dc",
            blue: "#8caaee", lavender: "#babbf1",
            text: "#c6d0f5", subtext1: "#b5bfe2", subtext0: "#a5adce",
            overlay2: "#949cbb", overlay1: "#838ba7", overlay0: "#737994",
            surface2: "#626880", surface1: "#51576d", surface0: "#414559",
            base: "#303446", mantle: "#292c3c", crust: "#232634"
        },
        macchiato: {
            rosewater: "#f4dbd6", flamingo: "#f0c6c6", pink: "#f5bde6", mauve: "#c6a0f6",
            red: "#ed8796", maroon: "#ee99a0", peach: "#f5a97f", yellow: "#eed49f",
            green: "#a6da95", teal: "#8bd5ca", sky: "#91d7e3", sapphire: "#7dc4e4",
            blue: "#8aadf4", lavender: "#b7bdf8",
            text: "#cad3f5", subtext1: "#b8c0e0", subtext0: "#a5adcb",
            overlay2: "#939ab7", overlay1: "#8087a2", overlay0: "#6e738d",
            surface2: "#5b6078", surface1: "#494d64", surface0: "#363a4f",
            base: "#24273a", mantle: "#1e2030", crust: "#181926"
        },
        mocha: {
            rosewater: "#f5e0dc", flamingo: "#f2cdcd", pink: "#f5c2e7", mauve: "#cba6f7",
            red: "#f38ba8", maroon: "#eba0ac", peach: "#fab387", yellow: "#f9e2af",
            green: "#a6e3a1", teal: "#94e2d5", sky: "#89dceb", sapphire: "#74c7ec",
            blue: "#89b4fa", lavender: "#b4befe",
            text: "#cdd6f4", subtext1: "#bac2de", subtext0: "#a6adc8",
            overlay2: "#9399b2", overlay1: "#7f849c", overlay0: "#6c7086",
            surface2: "#585b70", surface1: "#45475a", surface0: "#313244",
            base: "#1e1e2e", mantle: "#181825", crust: "#11111b"
        },
        latte: {
            rosewater: "#dc8a78", flamingo: "#dd7878", pink: "#ea76cb", mauve: "#8839ef",
            red: "#d20f39", maroon: "#e64553", peach: "#fe640b", yellow: "#df8e1d",
            green: "#40a02b", teal: "#179299", sky: "#04a5e5", sapphire: "#209fb5",
            blue: "#1e66f5", lavender: "#7287fd",
            text: "#4c4f69", subtext1: "#5c5f77", subtext0: "#6c6f85",
            overlay2: "#7c7f93", overlay1: "#8c8fa1", overlay0: "#9ca0b0",
            surface2: "#acb0be", surface1: "#bcc0cc", surface0: "#ccd0da",
            base: "#eff1f5", mantle: "#e6e9ef", crust: "#dce0e8"
        }
    })

    // Current raw palette (named colors: Theme.c.mauve, ...).
    readonly property var c: palettes[name] ?? palettes.macchiato

    // Semantic roles — prefer these in widgets so a palette swap Just Works.
    readonly property color background:    c.base
    readonly property color backgroundAlt: c.mantle
    readonly property color surface:       c.surface0
    readonly property color surfaceAlt:    c.surface1
    readonly property color overlay:       c.overlay0
    readonly property color border:        c.surface2
    readonly property color text:          c.text
    readonly property color subtext:       c.subtext0
    readonly property color accent:        c.mauve
    readonly property color accentAlt:     c.lavender
    readonly property color success:       c.green
    readonly property color warning:       c.yellow
    readonly property color error:         c.red

    // One knob for how big the shell is. Store-backed, so a panel swap or a
    // change of mind is `ipc call theme scale 1.4` rather than an edit tour of
    // forty files. Every size below derives from it; widgets name steps, never
    // pixels.
    readonly property real scale: store.get("scale") ?? 1.25

    // Type scale — five steps on a ~1.15 ratio. Base values are what the shell
    // used before it had a scale, so `scale: 1` reproduces the old sizes.
    readonly property var fs: ({
        xs: Math.round(11 * scale),   // dense labels: tooltips, secondary counts
        sm: Math.round(12 * scale),   // small chips and captions
        md: Math.round(14 * scale),   // the bar's own size, and body text
        lg: Math.round(16 * scale),   // section headings inside panels
        xl: Math.round(20 * scale)    // panel titles
    })

    // Space scale — the same five steps for padding and layout gaps.
    readonly property var space: ({
        xs: Math.round(2 * scale),
        sm: Math.round(4 * scale),
        md: Math.round(8 * scale),
        lg: Math.round(12 * scale),
        xl: Math.round(16 * scale)
    })

    // Shape tokens. Radii deliberately do NOT scale: a corner that grows with
    // the font stops reading as the same shape, and the whole look depends on
    // staying short of the lozenge.
    readonly property int radius: 6
    readonly property int radiusSmall: 4
    readonly property int radiusPill: 10   // rounded module pills (workspaces, clock)
    readonly property int radiusIsland: 12 // the bar's floating cards — a surface, not a button

    // Spacing aliases kept so existing call sites keep working; both are just
    // steps on `space`.
    readonly property int gap: space.lg
    readonly property int pad: space.xl

    // How tall the bar stands. Anything that has to sit clear of it reads this
    // rather than repeating a number: three surfaces used to carry their own
    // copy, and all three silently overlapped the bar the first time its height
    // changed.
    readonly property int barHeight: Math.round(30 * scale)

    // How far the islands float clear of the screen edge, and therefore how much
    // room anything anchored below the bar has to leave.
    readonly property int barInset: space.md
    readonly property int barReserved: barHeight + barInset * 2

    // Bar typography (JetBrainsMono Nerd Font 600).
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int barFontSize: fs.md
    readonly property int barFontWeight: Font.DemiBold

    // color + alpha (0..1) -> rgba, for translucent panels/backdrops.
    function withAlpha(color, a) {
        return Qt.rgba(color.r, color.g, color.b, a);
    }

    // ipc: qs -c quantumfate ipc call theme set <palette> | get | cycle | auto
    //      | scale <n> | opacity <n>
    IpcHandler {
        target: "theme"
        // Setting a palette by hand is a deliberate choice: it pins the mode so
        // the next sunrise does not undo it. `auto` hands the decision back.
        function set(palette: string): void {
            if (root.palettes[palette]) store.set({ palette: palette, mode: "manual" });
        }
        function get(): string { return root.name; }
        // Live size tuning: `theme scale 1.4`, then write the value you settle on
        // into the defaults. Clamped so a typo cannot make the shell unusable.
        function scale(value: real): real {
            const v = Math.max(0.8, Math.min(2.5, value));
            store.set({ scale: v });
            return v;
        }
        // Advance to the next palette in insertion order (wraps). An explicit
        // step is a deliberate choice, so it also pins the mode.
        function cycle(): string {
            const names = Object.keys(root.palettes);
            const next = names[(names.indexOf(root.name) + 1) % names.length];
            store.set({ palette: next, mode: "manual" });
            return next;
        }
        // Hand the choice back to the sun timer.
        function auto(): string {
            store.set({ mode: "auto" });
            return "auto";
        }
        // The global window-opacity dial. 1 = everything opaque, which is also
        // presentation mode.
        function opacity(value: real): real {
            const v = Math.max(0.5, Math.min(1.0, value));
            store.set({ opacity: v });
            return v;
        }
    }
}
