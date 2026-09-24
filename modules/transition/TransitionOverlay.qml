// Mode transition veil (LEO-423): a full-screen, opaque, blurred wallpaper the
// shell shows while a hyprfocus mode is applied.
//
// Why this and not a translucent scrim: a mode apply rearranges the whole desk
// and the user should not watch any of it. A mostly-opaque scrim still leaks
// the churn underneath, and a translucent compositor blur fights the shell's
// own fade. Instead the current wallpaper is drawn again, opaque, blurred, with
// the mode's own label centered on it — the desk is completely hidden for the
// transition, and the reveal is a single fade.
//
// Coverage: `exclusionMode: ExclusionMode.Ignore` is load-bearing. A
// four-sided layer surface is shrunk by every OTHER surface's exclusive zone,
// and the bar reserves a top strip (`quickshell-bar-reserve`); without Ignore
// this veil starts below the bar and is visibly cut off at the top, exactly as
// the bar's own overlay comment warns.
//
// Mapped for the whole session (verified live, LEO-423 follow-up): a layer
// surface that unmaps at one settle and remaps for the next transition commits
// exactly one frame after remapping and then never renders again — whatever
// the first frame did not carry never appears, which is why the veil
// previously read as "not there at all". A permanently mapped surface keeps
// its render loop (the bar is the proof), so every state change below actually
// reaches the screen. While idle the surface is fully transparent and its
// input mask is empty, so it is invisible to both the eye and the pointer.
//
// The show/hide is a snap, not a fade. The compositor suspends its own
// animations for the whole apply, so there is no continuous desk to fade
// against, and the earlier Behavior-driven fades left the item tree in
// cross-bracket states that could render the veil at a stuck partial opacity —
// the one failure this surface must never have. `Focus.motionEnergy` still
// reads the mood's contract, but the veil's correctness never depends on it.
//
// Timing: the compositor holds `hyprfocus.transition` present for the whole
// apply plus its settle (hypr's hypr/lib/transition.lua), with compositor
// animations and open-time focus suspended throughout, and defers the
// rearrangement until after this surface has mapped, so the desk never blinks
// through a half-drawn veil. A reload's apply never sets `present`, so a
// config save does not flash the veil. This component simply follows the
// flag, so the two ends cannot disagree.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import "../../services"

Scope {
    id: root

    Store {
        id: transitionStore
        name: "hyprfocus.transition"
        defaults: ({ active: false, present: false })
    }

    readonly property bool active: transitionStore.get("present") === true
    // The mode the compositor is transitioning to; fall back to the pointer's
    // effective mode for the tick before the store write lands.
    readonly property string mode: transitionStore.get("mode") ?? Hyprfocus.mode
    readonly property string label: Hyprfocus.label(root.mode)

    // The shell-side watchdog, the last line of defence against a stuck veil:
    // the compositor's own failsafe (hypr's hypr/lib/transition.lua) settles a
    // bracket whose finish never came, but if the compositor itself is wedged
    // the store write never lands. The veil must never become a room the user
    // cannot leave, so past the published duration plus a margin the overlay
    // force-hides locally, whatever the store still says. One-shot per
    // bracket: armed on active, cancelled by the normal settle, never carried
    // across brackets.
    property int _watchdogMs: 0
    // What the Variants delegate shows. The watchdog short-circuits it.
    readonly property bool shown: root.active && !root.watchdogFired
    property bool watchdogFired: false

    onActiveChanged: {
        watchdog.stop();
        root._watchdogMs = 0;
        if (root.active) {
            // A covered desk produces no compositor damage, so nothing after
            // the first committed frame is guaranteed to render (verified
            // live: the countdown sat frozen for a whole bracket). The veil
            // is therefore static by design — label only, no countdown, no
            // progress line.
            root._watchdogMs = (transitionStore.get("duration_ms") ?? 0) + 4500;
            watchdog.interval = Math.max(1000, root._watchdogMs);
            watchdog.restart();
        } else {
            root.watchdogFired = false;
        }
    }

    Timer {
        id: watchdog
        repeat: false
        onTriggered: {
            if (!root.active) return;
            root.watchdogFired = true;
            console.warn("transition veil: compositor never settled within "
                + root._watchdogMs + " ms; force-hiding locally");
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            // Mapped for the whole session — see the header for why this
            // surface must never unmap/remap.
            visible: true
            // Idle: fully transparent, nothing of the desk is covered. Live:
            // the surface's own opaque ground, so even mid-fade nothing of the
            // rearranging desk could show through.
            color: root.shown ? Theme.background : "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            // Span the whole output, under the bar included — see the header.
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Overlay
            // The desk is hidden, so keys must not reach it. The veil takes
            // them for the transition instead of acting on unseen windows.
            WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-transition"
            // Click-through while idle: the always-mapped overlay must be
            // invisible to the pointer too, or it would eat every click on
            // the desk. While the bracket is up the whole surface takes
            // input — there is nothing behind it worth clicking.
            mask: root.shown ? fullSurface : noSurface
            Region { id: fullSurface; item: veil }
            Region { id: noSurface }

            // The wallpaper bound to this output: `wallpapers[palette]` is
            // either a per-output map or a bare `palette/file` string, resolved
            // against the wallpapers root the same way `,theme.sh` does. A
            // leading "/" is already absolute.
            readonly property string wallpaper: {
                const w = Theme.wallpapers[Theme.name];
                let rel = "";
                if (w && typeof w === "object") rel = w[win.modelData.name] ?? w["*"] ?? "";
                else if (typeof w === "string") rel = w;
                if (!rel) rel = Theme.wallpaper;
                if (!rel) return "";
                return rel.startsWith("/") ? ("file://" + rel) : ("file://" + Theme.wallpaperRoot + "/" + rel);
            }

            Item {
                id: veil
                anchors.fill: parent
                // A snap: the window's own color, keyboard focus and input
                // mask flip with the same flag, so a half-shown veil is not a
                // state the surface can be observed in.
                opacity: root.shown ? 1 : 0
                visible: root.shown

                // Opaque ground first: even with no wallpaper resolvable, the
                // rearranging desk is never visible through the veil.
                Rectangle { anchors.fill: parent; color: Theme.background }

                Image {
                    id: wallpaper
                    anchors.fill: parent
                    // A binding that does not exist on disk falls through to the
                    // palette's own `<palette>.jpg`, the same first fallback
                    // `,theme.sh` takes, so a stale binding does not leave a
                    // blank veil.
                    property bool useFallback: false
                    readonly property string fallback: "file://" + Theme.wallpaperRoot + "/" + Theme.name + ".jpg"
                    source: wallpaper.useFallback ? wallpaper.fallback : win.wallpaper
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // MultiEffect renders the blurred copy; the raw image is
                    // only a source. The opaque ground above is the loading
                    // fallback until this image is ready.
                    visible: false
                    onStatusChanged: if (status === Image.Error && !wallpaper.useFallback) wallpaper.useFallback = true
                    Connections {
                        target: win
                        function onWallpaperChanged() { wallpaper.useFallback = false; }
                    }
                }

                MultiEffect {
                    anchors.fill: parent
                    source: wallpaper
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 64
                    autoPaddingEnabled: false
                }

                // A light wash of the scrim keeps text legible over the blur
                // without hiding it.
                Rectangle { anchors.fill: parent; color: Theme.withAlpha(Theme.scrim, 0.32) }

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.space.lg

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Entering"
                        color: Theme.subtext
                        font.pixelSize: Theme.fs.md
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.label
                        color: Theme.text
                        font { pixelSize: Theme.fs.xl; bold: true }
                    }
                }
            }
        }
    }
}
