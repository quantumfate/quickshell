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
import "PaletteLease.js" as PaletteLease

Singleton {
    id: root

    // The clock a day/night palette pair (LEO-365) leases against: local
    // hour is all `PaletteLease.leasedPalette` needs, so the shell flips its
    // own lease at 07:00/19:00 with no help from the compositor.
    SystemClock { id: clock; precision: SystemClock.Hours }

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
            transparency: 1.0,      // global window-transparency dial (0 = opaque)
            wallpaper_blur: 18,     // wallpaper backdrop sigma; 0 = no blur
            wallpaper_blurs: ({}),  // output -> blur sigma
            wallpaper: "",          // "" = the palette's default, resolved by ,theme.sh
            wallpapers: ({}),       // palette -> wallpaper; `wallpaper` is the fallback
        })
    }

    readonly property string name: withLease(lease, store.get("palette") ?? "macchiato")

    // The palette a mode leases while it runs (LEO-288): the declaration names
    // one in the mode's `presentation`, the pointer says whether the mode is
    // on, and the lease is in effect only then. "", or a name no palette
    // answers to, means "no lease". The baseline stays in the store untouched
    // — a mode holds the palette the way it holds a window, and gives it back
    // when the mode ends — so the sun timer and a manual pick outlast any
    // mood, and the lease is the ONE thing that changes on entry.
    readonly property string lease:
        (Hyprfocus.known && Focus.active)
            ? PaletteLease.leasedPalette(Hyprfocus.presentation.palette, clock.date.getHours())
            : ""
    function withLease(lease, baseline) {
        return (lease && root.palettes[lease]) ? lease : baseline;
    }

    // The one fan-out a lease owes. Called from Focus's mode-change seam
    // (the same place the compositor converge and the scene apply fire) AND
    // on the clock's own hourly tick below.
    //
    // "did the resolved palette actually move" used to be answered here in
    // JS, from PaletteLease.js plus a raw store read — but that path only
    // knew about a MODE's own lease. A desk in plain `mode: "auto"` with no
    // lease-bearing mode active has no lease at all, so `held` was always ""
    // and `now` was always just `store.get("palette")` unchanged — nothing
    // here ever noticed the sun cross 07:00/19:00, so the hourly tick fanned
    // out only by accident, when the active mode's own lease happened to
    // move too (LEO-398: the fan-out is what pokes kitty/GTK/Obsidian/
    // Linear/the browser, so a desk that never fans out sees the shell and
    // terminal drift day/night while everything else stays put).
    //
    // `,theme.sh get` prints the exact same `resolve()` a manual
    // `set`/`toggle`/`apply` uses — lease, THEN the auto/manual baseline. So
    // asking the script instead of re-deriving the answer here means the
    // automatic and manual paths share one resolver, and can never disagree
    // about when a fan-out is owed.
    property string _applied: root.name
    Process {
        id: resolvedPoll
        command: [",theme.sh", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const now = text.trim();
                // Only a real move fans out: a lease naming the palette
                // already showing runs nothing (the fan-out reloads Hyprland
                // and resets every window border, which is noise when
                // nothing recolours — the fan-out belongs to the palette,
                // not to the mode switch).
                if (!now || now === root._applied) return;
                root._applied = now;
                root.applyToSystem();
            }
        }
    }
    function noteLease() {
        resolvedPoll.running = false;
        resolvedPoll.running = true;
    }
    // A day/night pair (LEO-365) flips on its own at 07:00/19:00 with no
    // mode transition involved, so the hourly tick owes the same fan-out.
    Connections {
        target: clock
        function onDateChanged() { root.noteLease(); }
    }
    function applyToSystem() {
        root._applied = root.name;
        fanOut.running = false;
        fanOut.running = true;
    }

    // How the palette is chosen. "auto" hands the decision to the sun timer;
    // "manual" means a deliberate pick that outlasts the next sunrise.
    readonly property string mode: store.get("mode") ?? "auto"
    readonly property string dayPalette: store.get("day") ?? "latte"
    readonly property string nightPalette: store.get("night") ?? "macchiato"

    // Read by the Hyprland opacity rules rather than by the shell itself: one
    // dial over the whole role table. 0 is a hard "everything opaque", which is
    // presentation mode; 1 gives each role the transparency it was designed
    // with. Named for what you turn up, because a dial called `opacity` that
    // you turn DOWN to get transparency reads backwards every time.
    readonly property real transparency: store.get("transparency") ?? 1.0

    // The wallpaper backdrop blur sigma, 0..48, 0 = no blur. The render is
    // owned by ,theme.sh's process_wallpaper, which reads this same key and
    // bakes the value into its cache stamp — the shell only dials it.
    readonly property int wallpaperBlur: store.get("wallpaper_blur") ?? 18

    // Per-output wallpaper blur overrides (output -> sigma). Falls back to
    // wallpaperBlur (and ultimately 18) for any monitor not explicitly keyed.
    readonly property var wallpaperBlurs: store.get("wallpaper_blurs") ?? ({})
    function blurForOutput(output) {
        return (output && root.wallpaperBlurs[output] !== undefined)
            ? root.wallpaperBlurs[output]
            : root.wallpaperBlur;
    }

    // "" means the palette decides; `,theme.sh` resolves and applies it.
    readonly property string wallpaper: store.get("wallpaper") ?? ""

    // Wallpaper per palette. The image that reads well behind Latte is rarely
    // the one that reads well behind Mocha, so the binding is per palette and
    // `wallpaper` is only the fallback.
    readonly property var wallpapers: store.get("wallpapers") ?? ({})
    function wallpaperFor(palette) {
        return wallpapers[palette] ?? wallpaper;
    }

    // The hand tables: the seed the packs derive over. Kept as the load-time
    // fallback and the lockstep reference: the pack files derive over it, so a
    // pack that cannot answer keeps the desk working, and a pack proven equal
    // replaces it when it settles.
    readonly property var _seedPalettes: ({
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

    // Everything the switch speaks: the seed, with every pack's derived
    // variants merged over it. `cycle` walks them in insertion order.
    readonly property var palettes: Packs.settled
        ? Object.assign({}, _seedPalettes, Packs.palettes)
        : _seedPalettes


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
    // The palette stays the source of truth; the active mood only picks
    // which role stands in for "accent" (Focus.accentRole names a role on
    // `c`, never a literal colour — see Focus.qml's `moods` table). This is
    // a plain binding, not a process/side-effect, so it re-fires reliably on
    // every mood change with no call to `applyToSystem()` — see that
    // function's comment for the one case that genuinely needs the explicit
    // call instead of a binding.
    //
    // The light-palette contrast guard lives in `roleFor`, and is the same
    // set colors.lua and ,theme.sh's accent_role pin: on latte only mauve and
    // blue clear the accent-on-base target, so a pale role (lavender, peach,
    // yellow, …) stands in as mauve; dark palettes pass every role.
    function roleFor(palette, role) {
        return (palette === "latte" && role !== "mauve" && role !== "blue") ? "mauve" : role;
    }
    readonly property color accent:        c[roleFor(name, Focus.accentRole)] ?? c.mauve
    readonly property color accentAlt:     c.lavender
    readonly property color success:       c.green
    readonly property color warning:       c.yellow
    readonly property color error:         c.red
    readonly property color info:          c.blue
    readonly property color pending:       c.peach

    // A second tier below `subtext`: for a line that must stay readable but
    // reads quieter still (a caption under a secondary label).
    readonly property color subtextAlt:    c.subtext1

    // A second accent hue distinct from `accent`/`accentAlt` (mauve/lavender):
    // for "ok, and separately notable" state — a clean git tree, a live
    // connection — that shouldn't compete visually with `success`'s pass/fail
    // green.
    readonly property color accentSecondary: c.teal

    // The tier under `backgroundAlt`: the scrim behind a modal, and any sunken
    // inset well (e.g. a search field) that should look pressed into the
    // surface rather than sitting on it.
    readonly property color scrim:         c.crust
    readonly property color inset:         c.crust

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
    // Paper, not glass. A sheet has a crisp edge and barely any curve, so every
    // radius here is a hint that a corner exists rather than a shape in itself.
    // Nothing in the shell is a lozenge.
    readonly property int radius: 3
    readonly property int radiusSmall: 2
    readonly property int radiusPill: 3
    readonly property int radiusIsland: 4

    // Named alpha steps for the shared card material (modules/common/Surface.qml).
    // These are NOT free to tune in isolation: the compositor only blurs a layer
    // surface above its own `ignore_alpha` threshold, set per WlrLayershell
    // namespace in the hypr repo (hypr/hypr/layerrules.lua). Bump a step here and
    // check every layer rule whose surfaces use it still sits below the new
    // value, or the card silently stops being frosted.
    // Paper is opaque. These sit high enough that text is read against a sheet
    // rather than against whatever the wallpaper is doing, and just under 1 so
    // the compositor still frosts what little shows through.
    // `island`/`modal`/`peek` all track the active mood's single surfaceAlpha
    // dial (Focus.surfaceAlpha) rather than each other: a mood is one "how
    // much paper vs glass" setting for every translucent card in the shell,
    // not a per-surface tune. `backdrop`/`solid` stay fixed — a scrim reads
    // the same in every mood, and `solid` has no frosting to modulate.
    readonly property var surfaceAlpha: ({
        island:   Focus.surfaceAlpha,  // bar clusters — ignore_alpha 0.55 (quickshell-bar)
        modal:    Focus.surfaceAlpha,  // focused cards over a dim backdrop — ignore_alpha 0.6 (…cheatsheet, …window-rename), 0.1 (…team-selector)
        backdrop: 0.5,   // the dim scrim behind a modal — must stay under its modal's ignore_alpha
        peek:     Focus.surfaceAlpha,  // lighter, non-interactive glance panels — ignore_alpha 0.1 (…cheatsheet-peek)
        solid:    1.0    // fully opaque, no frosting needed
    })

    // Spacing aliases kept so existing call sites keep working; both are just
    // steps on `space`.
    readonly property int gap: space.lg
    readonly property int pad: space.xl

    // Motion roles. One place a duration is named, gated by the mood's motion
    // contract (`Focus.motionEnergy`): an `instant` mood collapses every
    // duration to zero — no motion, not a smaller number — while `base` keeps
    // the felt timings. `exit` is shorter than `enter` on purpose: leaving
    // should never feel like it is being watched. Widgets that animate read
    // these rather than carrying their own milliseconds.
    readonly property var motion: ({
        fast: Focus.motionEnergy === "instant" ? 0 : 90,
        base: Focus.motionEnergy === "instant" ? 0 : 150,
        slow: Focus.motionEnergy === "instant" ? 0 : 220,
        exit: Focus.motionEnergy === "instant" ? 0 : 120,
        ease: Easing.OutCubic
    })

    // Toast stack width, and the history panel's ceiling. Named here so the
    // notification surfaces stay one size across moods and scale together.
    readonly property int toastWidth: Math.round(380 * scale)
    readonly property int historyWidth: Math.round(640 * scale)

    // How tall the bar stands. Anything that has to sit clear of it reads this
    // rather than repeating a number: three surfaces used to carry their own
    // copy, and all three silently overlapped the bar the first time its height
    // changed.
    readonly property int barHeight: Math.round(26 * scale)

    // How far the islands float clear of the screen edge, and therefore how much
    // room anything anchored below the bar has to leave.
    readonly property int barInset: space.md
    readonly property int barReserved: barHeight + barInset * 2

    // Bar typography (JetBrainsMono Nerd Font 600).
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int barFontSize: fs.md
    readonly property int barFontWeight: Font.DemiBold

    // ---- wallpaper browsing (LEO-366) --------------------------------------
    // Mutation always shells out to `,theme.sh wallpaper ...` — this file
    // never writes `wallpapers`/`wallpaper_shuffle` to the store itself; the
    // script is the one writer (bin/,theme.sh in the hypr repo) and it saves,
    // shuffles, and repaints the live desktop when the palette is the one
    // showing. `wallpaperFor`/`wallpapers` above stay read-only mirrors of
    // whatever it last wrote.
    readonly property string wallpaperRoot: Quickshell.env("HOME") + "/.config/hypr/wallpapers"

    // The last `wallpaper list` result: {palette, monitors: {NAME: {current,
    // index}}, count, items}. "" until the first refresh.
    property var wallpaperSet: ({ palette: "", monitors: ({}), count: 0, items: [] })

    Process {
        id: wallpaperLister
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.wallpaperSet = JSON.parse(text); }
                catch (e) { console.warn("theme: bad `wallpaper list` JSON"); }
            }
        }
    }
    function wallpaperRefresh(palette) {
        wallpaperLister.command = [",theme.sh", "wallpaper", "list", palette];
        wallpaperLister.running = true;
    }

    // One mutator process for next/prev/random/pick/blur, with a QUEUE behind
    // it. A single slot used to mean two quick "next" clicks overwrote the
    // command of the process already running — the second click silently did
    // nothing, which is what made the browser's arrows feel wonky. Mutations
    // now run in order.
    //
    // It deliberately does NOT re-list on exit any more. `wallpaper list` costs
    // ~1s (it scans every palette folder and each image's real pixel size), and
    // running it after every step put that second between the click and the
    // thumbnail. The panel reads the live pick straight from the `wallpapers`
    // key the script writes to theme.json (see ControlPanel's `currentFor`),
    // which the store already watches; the expensive list is refreshed only
    // when the browser opens or its palette changes.
    Process {
        id: wallpaperMutator
        property var queue: []
        onExited: {
            if (wallpaperMutator.queue.length > 0) {
                wallpaperMutator.command = wallpaperMutator.queue.shift();
                wallpaperMutator.running = true;
            }
        }
    }
    function _runWallpaper(args) {
        const command = [",theme.sh", "wallpaper"].concat(args);
        if (wallpaperMutator.running) wallpaperMutator.queue.push(command);
        else { wallpaperMutator.command = command; wallpaperMutator.running = true; }
    }
    function wallpaperNext(palette, output) {
        root._runWallpaper(output ? ["next", palette, "--output", output] : ["next", palette]);
    }
    function wallpaperPrev(palette, output) {
        root._runWallpaper(output ? ["prev", palette, "--output", output] : ["prev", palette]);
    }
    function wallpaperRandom(palette, output) {
        root._runWallpaper(output ? ["random", palette, "--output", output] : ["random", palette]);
    }
    // Sets blur sigma for one monitor (or globally when output is omitted/empty),
    // persisting to theme.json and repainting live through ,theme.sh.
    function setWallpaperBlur(palette, output, sigma) {
        root._runWallpaper(output ? ["blur", sigma.toString(), palette, "--output", output] : ["blur", sigma.toString(), palette]);
    }
    // Binds one specific file (validated by the script against the palette's
    // set folder) — the `--action` target for the feh viewer below.
    function wallpaperPick(file, palette) {
        root._runWallpaper([file, palette]);
    }

    // The full-size viewer (LEO-366): feh over the palette's own set folder,
    // scaled to fit the given geometry. Return re-binds the image on screen
    // back to the palette through the same script `wallpaperPick` uses —
    // still no direct store write, even from inside feh. Stepping
    // (space/backspace) and quitting (q) are feh's own defaults; nothing to
    // wire by hand for those.
    //
    // The hypr-side windowrule (hypr/windowrules.lua, matched on feh's WM_CLASS
    // "feh") floats, centers and caps the window to the monitor minus
    // default_gaps' outer margin — that rule is the source of truth for the
    // final size. `--geometry` here only sets feh's own starting guess so its
    // internal scale-down math isn't computed against the full monitor before
    // Hyprland resizes it: the caller already passes a gap-shrunk size (see
    // ControlPanel.qml), not the raw screen dimensions.
    Process { id: viewer }
    function openWallpaperViewer(palette, width, height) {
        const dir = root.wallpaperRoot + "/" + palette;
        const geometry = Math.round(width) + "x" + Math.round(height);
        viewer.command = ["feh", "--scale-down", "--auto-zoom", "--geometry", geometry,
            "--title", "wallpapers — " + palette,
            "--action", ",theme.sh wallpaper %F " + palette,
            dir];
        viewer.running = true;
    }

    // The fan-out belongs to the palette, not to whoever changed it — and not
    // to a mood switch. `accent`/`surfaceAlpha` above are plain bindings on
    // Focus.mode; kitty/GTK/Qt already recolour the moment `,theme.sh apply`
    // runs for the *palette*, and re-running it on every mood change would
    // reset every window border for a change none of those apps render
    // anyway. Only `applyToSystem()` below reaches this process.
    //
    // Quickshell and Hyprland watch this store and react on their own, but
    // kitty, GTK, Qt, Kvantum and the wallpaper need a process to poke them.
    // Hanging that off each writer meant the control centre fanned out and
    // `ipc call theme set` did not, so a palette switch from a keybind left the
    // window borders and every Qt app on the old colours.
    //
    // `,theme.sh apply` writes the resolved palette back to this same store, but
    // with the value it just read, so `name` does not change again and this does
    // not loop.
    // Called by every writer rather than bound to `name`: a binding on a
    // readonly property fed by a store read did not re-fire reliably, so a
    // palette set from a keybind left the borders and every Qt app behind
    // while the shell itself had already recoloured.
    Process { id: fanOut; command: [",theme.sh", "apply"] }

    // color + alpha (0..1) -> rgba, for translucent panels/backdrops.
    function withAlpha(color, a) {
        return Qt.rgba(color.r, color.g, color.b, a);
    }

    // ipc: qs -c quantumfate ipc call theme set <palette> | get | cycle | auto
    //      | scale <n> | transparency <n>
    IpcHandler {
        target: "theme"
        // Setting a palette by hand is a deliberate choice: it pins the mode so
        // the next sunrise does not undo it. `auto` hands the decision back.
        function set(palette: string): void {
            if (!root.palettes[palette]) return;
            store.set({ palette: palette, mode: "manual" });
            root.applyToSystem();
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
            root.applyToSystem();
            return next;
        }
        // Hand the choice back to the sun timer.
        function auto(): string {
            store.set({ mode: "auto" });
            root.applyToSystem();
            return "auto";
        }
        // The global transparency dial. 0 = everything opaque (presentation
        // mode), 1 = each role at the transparency it was designed with.
        function transparency(value: real): real {
            const v = Math.max(0.0, Math.min(1.0, value));
            store.set({ transparency: v });
            root.applyToSystem();
            return v;
        }
    }
}
