// Bar — the top bar, one instance per monitor. A status indicator, not a
// taskbar (LEO-221): four islands, nothing that duplicates what a Hyprland
// group's own groupbar already shows. The window list is gone from every
// workspace, including the gaming one — that workspace moves to a group in
// LEO-230, same as the project terminals already do.
//   bar.workspaces  where am I     — workspaces · submap indicator · group chip
//   dofus.roster    Dofus only     — appears on the gaming workspace
//   bar.center      what's playing — media · brightness · volume
//   bar.clock       when is it     — clock · mood · entry to the calendar centre
//
// Everything else (system info, background apps, logout, settings,
// diagnostics, tray, notifications) moved to the on-demand System Center
// (SysPanel.qml), reachable from which-key rather than sitting on the bar.
//
// LEO-420 (dock consumer): each isle above carries a stable id — the
// vocabulary hypr's scene documents speak (see Readme.md's Isle registry).
// The bar is one transparent, click-through overlay PanelWindow per monitor,
// anchored on all four sides with exclusiveZone 0: reserving space here would
// double-count the gutter hypr's scene gaps already carved, so every isle is
// positioned absolutely instead of laid out by the panel's own anchors. A
// docked isle reads its placement from the `geometry` store's
// `docks[screen][isleId]` document (services/DockPlacement.js does the math);
// with nothing published yet — or nothing published for that isle — it keeps
// today's resting position, so this ships ahead of the hypr side without
// breaking.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, Hyprfocus, PanelBus
import "../../services/BarGaps.js" as BarGaps
import "../../services/DockPlacement.js" as Dock
import "../common"        // Surface

Scope {
    id: scope

    // Monitors that must NOT carry the bar (the small portrait panel).
    readonly property var excludedScreens: ["HDMI-A-1"]

    // LEO-340: per-monitor base left/right outer gap, published by conf/host.lua
    // (hypr repo) so the bar's side insets line up with the tiled gap instead of
    // a constant. One shared Store instance: FileView.watchChanges means every
    // bar re-reads live (e.g. pulling the laptop's external monitor), no restart.
    Store { id: geometryStore; name: "geometry" }
    Store { id: hyprfocusStore; name: "hyprfocus" }

    // Bumped by the IPC `reveal` call below (bound to a SUPER-tap keybind in
    // the hypr repo) so every bar instance drops out of autohide at once.
    property int revealTick: 0

    IpcHandler {
        target: "bar"
        function reveal(): void { scope.revealTick++; }
    }

    // The workspace name active on each bar's screen is tracked in PanelBus
    // (singleton) so gap-aware surfaces outside the bar, like Toasts, can read
    // the same value without duplicating the raw-event listener. A scene edit
    // needs no event at all: the `hyprfocus` Store (above) re-reads the file
    // live, so `edgeInset` re-binds on either change — no reload, no poll.

    // Tooltip surfaces, one per bar screen (drawn below the bar by TipLayer).
    Variants {
        model: Quickshell.screens.filter(s => !scope.excludedScreens.includes(s.name))
        TipLayer { required property var modelData; screen: modelData }
    }

    // The strip the isles stand in, reserved from the tiling.
    //
    // A docked bar is one full-monitor, click-through overlay so an isle can
    // sit anywhere on the screen — and a full-monitor surface cannot also
    // reserve a top strip, since a layer surface's exclusive zone belongs to
    // the ONE edge it is anchored to. With the overlay reserving nothing, the
    // only thing carving a gutter for the isles was the scene's own top gap,
    // and a scene whose gap is thinner than an isle (obsidian-linear carved
    // 24px for a 54px isle) had its windows tiled straight under the bar.
    //
    // So the reservation moves to its own surface: zero-size, invisible,
    // click-through, anchored to the top edge, carrying nothing but the
    // exclusive zone. The compositor carves the strip, every scene's top
    // gutter clears an isle by construction, and the overlay stays free to
    // place isles wherever the desk publishes them. Only while docked — an
    // undocked bar is still the strip it always was and reserves its own.
    Variants {
        model: Quickshell.screens.filter(s => !scope.excludedScreens.includes(s.name))

        PanelWindow {
            id: reserve
            required property var modelData
            screen: modelData

            readonly property var docksForScreen: (geometryStore.data?.docks || {})[reserve.screen.name]
            readonly property bool docked: {
                const docks = reserve.docksForScreen;
                if (!docks) return false;
                for (const id in docks) if (Dock.isPlaced(Dock.resolveDockMode(docks, id))) return true;
                return false;
            }

            visible: reserve.docked
            anchors { top: true; left: true; right: true }
            implicitHeight: 0
            exclusiveZone: reserve.docked ? Theme.barReserved : 0
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-bar-reserve"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // Nothing here is ever clickable: an empty mask, not merely a
            // transparent surface, or it would eat the top edge of the screen.
            mask: Region {}
        }
    }

    Variants {
        model: Quickshell.screens.filter(s => !scope.excludedScreens.includes(s.name))

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            // LEO-420: full-monitor, transparent, click-through overlay. NOT a
            // reserved strip — a docked isle must cost the tiling nothing, since
            // the scene's own gaps already carve its gutter. Anchoring all four
            // sides (rather than sizing to Theme.barReserved) is what lets an
            // isle dock anywhere on the screen, not just the old top strip.
            //
            // Until the hypr side publishes a dock for this screen there is
            // nothing to place anywhere but the old top strip, and a
            // zero-reservation full-screen overlay would let the windows take
            // the very top edge with the isles floating over them. So the
            // resting shell keeps the strip it always was -- anchored to the
            // top and reserving Theme.barReserved -- and only becomes the
            // four-sided overlay once a dock document actually arrives.
            anchors {
                top: true
                left: true
                right: true
                bottom: bar.docked
            }
            implicitHeight: bar.docked ? 0 : Theme.barReserved
            exclusiveZone: bar.docked ? 0 : Theme.barReserved
            // Reserving nothing is not the same as being positioned as if
            // nothing were reserved. A four-sided layer surface is shrunk by
            // every OTHER surface's exclusive zone -- the reserve strip above
            // is one, so this overlay's origin sat 58px below the monitor's
            // while hypr publishes monitor-local coordinates. Every isle was
            // drawn that far down, flush onto the window edge, and only the
            // vertical axis was wrong because the side zones are zero. Ignore
            // makes the overlay the whole output again, which is the frame
            // the published geometry is written in.
            exclusionMode: bar.docked ? ExclusionMode.Ignore : ExclusionMode.Normal
            color: "transparent"

            // This screen has at least one isle the desk actually placed.
            // Counting every key (what this did first) counted `hidden` and
            // `resting` documents too, so a scene that publishes an isle it
            // withholds still dropped the reserved strip and let the windows
            // tile under the bar. Only a mode that carries geometry counts.
            readonly property bool docked: {
                const docks = bar.docksForScreen;
                if (!docks) return false;
                for (const id in docks) if (Dock.isPlaced(Dock.resolveDockMode(docks, id))) return true;
                return false;
            }

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-bar"
            // Accept the keyboard only while a chip on THIS screen is being
            // renamed. OnDemand (NOT Exclusive): the compositor keeps control and
            // restores focus normally — an Exclusive grab left dangling by a
            // destroyed surface locks up keyboard input system-wide. None the
            // rest of the time so clicking the bar never steals focus.
            WlrLayershell.keyboardFocus: (BarInput.renaming && BarInput.screen === bar.screen.name)
                ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Click-through everywhere except the isles themselves: the union
            // of their bounding rects is the only clickable area, so the
            // overlay never eats a click meant for a window underneath. An
            // isle with zero size (hidden, per its dock document) contributes
            // an empty region.
            mask: Region {
                Region { item: leftIsland }
                Region { item: dofusIsle }
                Region { item: centerIsland }
                Region { item: rightIsland }
                // The reveal strip belongs in the mask too: while the isles are
                // slid out of view they contribute nothing, so without this the
                // pointer passes straight through the top edge and an autohidden
                // bar can only be brought back by the IPC keybind.
                Region { item: revealStrip }
            }

            // First eligible bar screen is the default target for the sysmon
            // keybind/IPC toggle (when no hover has set an anchor yet).
            Component.onCompleted: if (!SysMon.homeScreen) SysMon.homeScreen = bar.screen.name;

            // --- Autohide (LEO-221): honours the declaration rather than a
            // local guess. `deep`/`game` (the old shedding/autohide ids) are
            // retired (see hypr AGENTS.md's mode-id contract); the current
            // modes speak through `presentation.bar_autohide` instead
            // (work/study autohide, neutral/gaming stay put) — no mode today
            // declares zone-shedding on top of that, so this bar no longer
            // has a `deepMode` concept to key off.
            readonly property bool autohideOn: Hyprfocus.current.presentation?.bar_autohide ?? false

            property bool revealed: true
            Connections { target: scope; function onRevealTickChanged() { bar.revealed = true; idle.restart(); } }

            Timer {
                id: idle
                interval: 2000
                running: bar.autohideOn && bar.revealed
                onTriggered: bar.revealed = false
            }
            // Any hover over the islands themselves counts as activity.
            function wake() { bar.revealed = true; idle.restart(); }

            // This screen's published dock documents, keyed by isle id — the
            // `geometry` store's `docks[screen]` map. Read defensively: an
            // isle with no entry here (a fresh install, or the hypr side not
            // caught up yet) resolves to "resting" (see DockPlacement.js).
            readonly property var docksForScreen: (geometryStore.data?.docks || {})[bar.screen.name]

            // LEO-340 + scene alignment: this screen's tiled outer gap.
            // An opt-in scene (bar_follows_scene_gaps) subscribes to the
            // resolved per-workspace gap hyprland publishes to the
            // `geometry` store's `workspaces` map — quickshell never
            // derives a gap, so the inset cannot drift from the tiling.
            // A resting bar uses the monitor's published gap, then the
            // default. The scene rung rides `scope.sceneByScreen`,
            // refreshed by the compositor's workspace events; both store
            // rungs ride the `geometry`/`hyprfocus` stores' watchChanges
            // (hyprland re-publishes on a scene edit). Either change
            // re-binds this live — a scene redraw or a workspace switch,
            // no reload.
            readonly property var edgeInset: BarGaps.insetFor(
                geometryStore.data, hyprfocusStore.data,
                PanelBus.sceneByScreen[bar.screen.name], bar.screen.name, Theme.barInset * 2)

            // The vertical centre of the old top strip — every isle's resting
            // (undocked) position keeps living there, unchanged from before
            // this overlay refactor.
            readonly property real restingY: (Theme.barReserved - Theme.barHeight) / 2

            // --- left isle: bar.workspaces ---
            DockedIsle {
                id: leftIsland
                isleId: "bar.workspaces"
                bar: bar
                restingX: bar.edgeInset.left
                restingY: bar.restingY

                Workspaces { screen: bar.screen }
                SubmapIndicator {}
                GroupChip {}
            }

            // --- dofus.roster: appears only on the gaming workspace while
            // Dofus clients are present. Its resting position keeps riding
            // the left isle's right edge, same as before this refactor. ---
            DockedIsle {
                id: dofusIsle
                isleId: "dofus.roster"
                bar: bar
                restingX: leftIsland.x + leftIsland.width + Theme.barInset * 2
                restingY: bar.restingY
                active: roster.shouldShow

                DofusRoster {
                    id: roster
                    screen: bar.screen
                    activeWorkspaceName: PanelBus.sceneByScreen[bar.screen.name] ?? ""
                }
            }

            // --- centre isle: bar.center ---
            DockedIsle {
                id: centerIsland
                isleId: "bar.center"
                bar: bar
                restingX: (bar.screen.width - width) / 2
                restingY: bar.restingY

                Media { screenName: bar.screen.name }
                Brightness { screenName: bar.screen.name }
                Pulseaudio { screenName: bar.screen.name }
            }

            // --- right isle: bar.clock (LEO-425) ---
            // mode pill · clock · notifications · power. The mood pill leads:
            // it carries the countdown until the mood ends, which is the one
            // thing you want while the rest of the bar drops away on autohide.
            DockedIsle {
                id: rightIsland
                isleId: "bar.clock"
                bar: bar
                restingX: bar.screen.width - bar.edgeInset.right - width
                restingY: bar.restingY

                ModePill { screenName: bar.screen.name }
                Clock { screenName: bar.screen.name }
                NotifIndicator { screenName: bar.screen.name }
                Wlogout {}
            }

            // Thin always-present strip at the true top edge: catches the
            // pointer even while the isles are slid out of view on autohide,
            // so autohide has a way back in besides the SUPER-tap IPC reveal.
            // Kept out of the click-through mask deliberately — this is the
            // ONE extra clickable strip the overlay adds on top of the isles.
            MouseArea {
                id: revealStrip
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 8
                hoverEnabled: true
                visible: bar.autohideOn
                onEntered: bar.wake()
            }
        }
    }

    // One isle, dock-aware. Wraps the island card (Surface + layout) with
    // LEO-420 placement: docked AND fallback both read
    // `bar.docksForScreen[isleId]` through DockPlacement.placeDock -- the
    // publisher resolves both to a full region/anchor/grow, and "fallback"
    // only says which rung of the ladder answered. Resting (no document, or
    // state "resting") uses the caller's restingX/restingY -- today's static
    // layout, untouched. `hidden` (the scene declared this isle `false`)
    // renders nothing.
    //
    // Autohide keeps riding the same y-slide it always has: it is applied
    // here as an offset on top of whatever placement mode chose, so a docked
    // isle still tucks away when the bar shrinks.
    component DockedIsle: Item {
        id: slot
        required property string isleId
        required property var bar               // the owning PanelWindow
        required property real restingX
        required property real restingY
        default property alias content: island.content
        property alias spacing: island.spacing
        property string orientation: "horizontal"
        // Drawn only while the isle has something to say. The dofus roster is
        // the case this exists for: it speaks for a workspace it is not always
        // on, and an Island wrapped around an invisible child is still a card.
        property bool active: true

        readonly property var dockDoc: slot.bar.docksForScreen ? slot.bar.docksForScreen[slot.isleId] : undefined
        readonly property string mode: Dock.resolveDockMode(slot.bar.docksForScreen, slot.isleId)

        // Whether the isle was clamped last time it was placed — the edge
        // `shouldWarnClamp` needs, and the only way to warn once per state
        // change rather than once per frame.
        property bool wasClamped: false

        // Pure — no side effects in the binding itself, so it can be
        // re-evaluated freely. The clamp-warning bookkeeping below reacts to
        // its value instead of living inside it.
        readonly property var placed: (Dock.isPlaced(slot.mode) && slot.dockDoc)
            ? Dock.placeDock(
                slot.dockDoc,
                { width: island.implicitWidth, height: island.implicitHeight },
                { width: slot.bar.screen.width, height: slot.bar.screen.height },
                slot.bar.restingY)
            : null

        onPlacedChanged: {
            if (!slot.placed) return;
            if (Dock.shouldWarnClamp(slot.wasClamped, slot.placed.clamped)) {
                // Name the numbers. "exceeds bounds" alone said nothing about
                // WHICH bound, so the only way to act on it was to go read the
                // published document by hand — and the usual cause is mundane:
                // a scene's outer gap a few pixels thinner than the isle.
                const r = slot.dockDoc.region;
                console.warn("dock " + slot.isleId + ": isle "
                    + Math.round(island.implicitWidth) + "x" + Math.round(island.implicitHeight)
                    + " does not fit its gutter " + Math.round(r.w) + "x" + Math.round(r.h)
                    + " (scene gap minus standoff); it sits flush to the screen edge instead");
            }
            slot.wasClamped = slot.placed.clamped;
        }
        onModeChanged: if (!Dock.isPlaced(slot.mode)) slot.wasClamped = false;

        visible: slot.active && slot.mode !== "hidden"
        // Plain Items (unlike Layout-managed ones) never self-size from
        // implicit* — bind width/height explicitly, since this Item sits
        // directly on the overlay rather than inside a Layout.
        implicitWidth: island.implicitWidth
        implicitHeight: island.implicitHeight
        width: implicitWidth
        height: implicitHeight

        readonly property real targetX: slot.placed ? slot.placed.x : slot.restingX
        readonly property real targetY: slot.placed ? slot.placed.y : slot.restingY

        // One animated transition for every state change (LEO-420 §5) — the
        // snap when a target window appears, disappears, or the isle falls
        // back. The autohide slide (the old `content.y` behaviour) rides the
        // same y as an additional offset, so the two motions never fight
        // over the property.
        x: slot.targetX
        y: slot.targetY + ((slot.bar.autohideOn && !slot.bar.revealed) ? -Theme.barReserved : 0)
        Behavior on x { NumberAnimation { duration: Theme.motion.base; easing.type: Theme.motion.ease } }
        Behavior on y { NumberAnimation { duration: Theme.motion.base; easing.type: Theme.motion.ease } }

        HoverHandler { onHoveredChanged: if (hovered) slot.bar.wake() }

        Island {
            id: island
            orientation: slot.orientation
        }
    }

    // A floating card of bar modules: Surface (the shared material) plus the
    // row/column layout the bar itself needs — Surface owns only
    // ground/border/radius, never layout, so this stays private to the bar
    // rather than living in modules/common. `orientation` picks the flow: a
    // vertical isle (LEO-420 §3) stacks its items instead of running them in
    // a row.
    component Island: Surface {
        id: island
        default property alias content: grid.data
        property alias spacing: grid.columnSpacing
        property string orientation: "horizontal"
        // Drawn only while the isle has something to say. The dofus roster is
        // the case this exists for: it speaks for a workspace it is not always
        // on, and an Island wrapped around an invisible child is still a card.
        property bool active: true

        elevation: "island"
        // Lean: the card is the content plus a hairline of breathing room,
        // not a strip. The floor keeps every isle the same height whatever
        // its contents, so the row still reads as one bar.
        implicitWidth: grid.implicitWidth + Theme.space.md * 2
        implicitHeight: Math.max(Theme.barHeight, grid.implicitHeight + Theme.space.xs * 2)
        width: implicitWidth
        height: implicitHeight

        GridLayout {
            id: grid
            anchors {
                fill: parent
                leftMargin: Theme.space.md
                rightMargin: Theme.space.md
                topMargin: Theme.space.xs
                bottomMargin: Theme.space.xs
            }
            flow: island.orientation === "vertical" ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rows: island.orientation === "vertical" ? -1 : 1
            columns: island.orientation === "vertical" ? 1 : -1
            rowSpacing: Theme.space.md
            columnSpacing: Theme.space.md
        }
    }
}
