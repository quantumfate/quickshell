// MoodPanel — the mood centre (LEO-237). The bar's way to both pick the active
// mood and read/edit that mood's policy: notifications, background work, launch
// aggression and scene reachability. Every control writes through
// Focus.patchMood straight into the mood-policy store, so the change is
// reflected by the running shell immediately — Notify's suppression reads
// Focus.notifications.policy, Theme's accent/surfaceAlpha read the same store,
// and the Hyprland event manager and launcher scripts read the identical file.
// Opened from ModePill via PanelBus, same single-window pattern as CalendarPanel.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, PanelBus, Focus, Hyprfocus, SceneVeto
import "../../services/ModeExplain.js" as ModeExplain
import "../../services/ModeAnnounce.js" as ModeAnnounce
import "../common"        // Surface

Scope {
    id: scope

    // The active mood and its policy record — re-read from Focus on every store
    // change, so the panel edits the same data the rest of the shell sees.
    readonly property string mood: Focus.mode
    readonly property var pol: Focus.current
    readonly property var bg: scope.pol.background || {}
    readonly property var notif: scope.pol.notifications || {}
    readonly property var launch: scope.pol.launches || {}
    readonly property var sceneMap: scope.pol.scenes || {}
    // Hyprfocus.ids() already excludes hidden modes (neutral's recovery
    // fallback, reached only from the hypr modes submap) by the declaration's
    // own `hidden` flag - reuse it rather than re-deriving the same list from
    // the policy store's keys.
    readonly property var moodIds: Hyprfocus.ids().filter(id => Focus.policyData[id])

    // The user-unit background tasks the policy names. Lives here (not in the
    // schema) because the list is a UI choice: what the desk actually runs.
    readonly property var bgTasks: ["theme-auto", "obsidian", "state-backup", "chezmoi", "audio-notify"]

    // Cap so the panel fits on a laptop screen; taller content scrolls instead
    // of clipping (fs.xl = the largest type step, so the cap scales with the UI).
    // How much the panel can grow before it scrolls. Both knobs are steps on
    // the type scale rather than pixel counts, so the laptop lid and the
    // ultrawide compute their own answers (LEO-297): the mode list, per-task
    // cycling and the transitions all fit without scroll on the desktop and
    // get one x-height more on the lid before the scroll takes over.
    readonly property real maxCardHeight: Theme.fs.xl * 34
    readonly property real maxCardWidth: Theme.fs.xl * 26

    function patch(p) { Focus.patchMood(scope.mood, p); }
    function adopt(id) { Focus.set(id, 0); }
    function stop() { Focus.stop(); }
    function closePanel() { PanelBus.close("mood"); }

    function untilLabel() {
        if (!Focus.until) return "";
        const ms = Date.parse(Focus.until) - Date.now();
        if (ms <= 0) return "";
        const m = Math.ceil(ms / 60000);
        return " · " + (m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m") + " left";
    }

    // A task's effective background level. The single definitional resolver
    // lives on Focus (backgroundTaskLevel) — the panel displays it, and
    // ,scene-apply.sh reads the same verdict at apply time, so the UI and the
    // systemd seam can never disagree. `prevent` beats `defer` beats `allow`;
    // a wildcard allow covers everything not listed.
    function taskLevel(task) { return Focus.backgroundTaskLevel(task); }

    // Cycle a task through unset -> defer -> prevent -> unset (LEO-252
    // retired the wildcard shape: not-listed IS allowed, so an explicit
    // "allow" state never carried information and the cycle shrinks to what
    // actually changes behavior).
    function cycleTask(task) {
        const seq = ["unset", "defer", "prevent"];
        const from = scope.taskLevel(task);
        const next = seq[(seq.indexOf(from) + 1) % seq.length];
        const defer = (scope.bg.defer || []).filter(t => t !== task);
        const prevent = (scope.bg.prevent || []).filter(t => t !== task);
        if (next === "defer") defer.push(task);
        else if (next === "prevent") prevent.push(task);
        scope.patch({ background: Object.assign({}, scope.bg, { defer: defer, prevent: prevent }) });
    }

    function sceneSummary() {
        const keys = Object.keys(scope.sceneMap);
        if (keys.length === 0) return "all scenes reachable";
        return keys.map(k => k + ": " + scope.sceneMap[k]).join(" · ");
    }

    // The explain half (LEO-280): the declaration as sentences. The pointer's
    // provenance stands so the panel answers "why is my desk like this"
    // without reading a file by hand; the rows read the ACTIVE mode's own
    // record. Unknown-pointer states say so rather than showing nothing.
    readonly property string provenance: ModeExplain.provenance(
        { source: Hyprfocus.source, set_at: Hyprfocus.setAt }, Focus.until)
    readonly property var explained: Hyprfocus.known ? ModeExplain.rows(Hyprfocus.current) : []

    // The transition preview: what entering a chip would take, named before
    // the mode is entered (the announce model's own line, not a rewrite).
    property string _preview: ""
    function hoverChip(id) {
        const spec = Hyprfocus.modes[id];
        const a = spec ? ModeAnnounce.announce(spec, Hyprfocus.label(id)) : null;
        scope._preview = a ? a.body : "nothing taken away · enforces immediately";
    }

    // A row of option chips; exactly one is highlighted. `stretch` makes it
    // share the row's width (used full-width); off + a preferredWidth makes a
    // compact selector next to a label.
    component SegRow: RowLayout {
        id: seg
        property var options: []
        property string value: ""
        property var onPick: null
        property bool stretch: true
        Layout.fillWidth: seg.stretch
        spacing: Theme.space.xs

        Repeater {
            model: seg.options
            delegate: Rectangle {
                id: opt
                required property string modelData
                readonly property bool active: opt.modelData === seg.value
                Layout.fillWidth: true
                implicitHeight: Theme.fs.sm + Theme.space.sm * 2 + 2
                radius: Theme.radiusSmall
                color: opt.active ? Theme.withAlpha(Theme.accent, 0.18) : Theme.withAlpha(Theme.surface, 0.5)
                border { width: 1; color: opt.active ? Theme.accent : Theme.withAlpha(Theme.border, 0.5) }
                Text {
                    anchors.centerIn: parent
                    text: opt.modelData
                    color: opt.active ? Theme.accent : Theme.subtext
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: opt.active ? Font.Bold : Font.Normal }
                    horizontalAlignment: Text.AlignHCenter
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: if (seg.onPick) seg.onPick(opt.modelData)
                }
            }
        }
    }

    // Small uppercase section heading, same voice as the calendar panel.
    component SectionTag: Text {
        id: tag
        required property string title
        text: tag.title.toUpperCase()
        color: Theme.subtext
        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: Font.Bold }
    }

    // A labelled option row: caption on the left, SegRow taking the rest.
    component FieldRow: RowLayout {
        id: field
        required property string label
        required property var options
        required property string value
        required property var onPick
        Layout.fillWidth: true
        spacing: Theme.space.md

        Text {
            Layout.preferredWidth: Theme.fs.xl * 5
            text: field.label
            color: Theme.subtext
            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
        }
        SegRow {
            stretch: false
            Layout.preferredWidth: Theme.fs.xl * 7
            options: field.options
            value: field.value
            onPick: field.onPick
        }
    }

    PanelWindow {
        id: win
        visible: PanelBus.open === "mood"
        screen: PanelBus.screenObject(PanelBus.anchorScreen)
        color: "transparent"

        anchors { top: true; left: true; right: true }
        margins { top: Theme.barReserved + Theme.space.xs }
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
                        // it is entered (LEO-280's read half) — and the vetoes
                        // the last transition honoured, so a refusal is
                        // visible in the panel the desk runs it from.
                        Text {
                            visible: scope._preview !== ""
                            Layout.fillWidth: true
                            text: scope._preview
                            color: Theme.subtextAlt
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }
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

                        // -- notifications: what is allowed on screen.
                        SectionTag { title: "notifications" }

                        FieldRow {
                            label: "policy"
                            options: ["all", "critical-only", "none"]
                            value: scope.notif.policy || "all"
                            onPick: (v) => scope.patch({ notifications: Object.assign({}, scope.notif, { policy: v }) })
                        }
                        FieldRow {
                            label: "position"
                            options: ["top-right", "bottom-right"]
                            value: scope.notif.position || "top-right"
                            onPick: (v) => scope.patch({ notifications: Object.assign({}, scope.notif, { position: v }) })
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.md
                            Text {
                                Layout.fillWidth: true
                                text: "queue while suppressed"
                                color: Theme.text
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                            }
                            SegRow {
                                stretch: false
                                Layout.preferredWidth: Theme.fs.xl * 5
                                options: ["on", "off"]
                                value: scope.notif.queue ? "on" : "off"
                                onPick: (v) => scope.patch({ notifications: Object.assign({}, scope.notif, { queue: v === "on" }) })
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.md
                            Text {
                                Layout.fillWidth: true
                                text: "digest on exit"
                                color: Theme.text
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                            }
                            SegRow {
                                stretch: false
                                Layout.preferredWidth: Theme.fs.xl * 5
                                options: ["on", "off"]
                                value: scope.notif.digest_on_exit ? "on" : "off"
                                onPick: (v) => scope.patch({ notifications: Object.assign({}, scope.notif, { digest_on_exit: v === "on" }) })
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: scope.notif.timeout === 0
                                ? "toasts stick until closed"
                                : "toasts auto-expire after " + Math.round(scope.notif.timeout / 1000) + "s"
                            color: Theme.subtextAlt
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                        // -- background: user-unit work the desk runs.
                        SectionTag { title: "background" }

                        Text {
                            Layout.fillWidth: true
                            text: "click a task to cycle unset → defer → prevent (nothing listed runs freely)"
                            color: Theme.subtextAlt
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.xs

                            Repeater {
                                model: scope.bgTasks
                                delegate: Rectangle {
                                    id: trow
                                    required property string modelData
                                    readonly property string lvl: scope.taskLevel(trow.modelData)
                                    Layout.fillWidth: true
                                    implicitHeight: Math.max(lvlChip.implicitHeight, taskLabel.implicitHeight) + Theme.space.sm * 2
                                    radius: Theme.radiusSmall
                                    color: Theme.withAlpha(Theme.surface, 0.35)

                                    RowLayout {
                                        anchors { fill: parent; leftMargin: Theme.space.sm; rightMargin: Theme.space.sm }
                                        spacing: Theme.space.sm

                                        Text {
                                            id: taskLabel
                                            Layout.fillWidth: true
                                            text: trow.modelData
                                            color: Theme.text
                                            font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            id: lvlChip
                                            implicitWidth: lvlText.implicitWidth + Theme.space.sm * 2
                                            implicitHeight: lvlText.implicitHeight + Theme.space.xs
                                            radius: Theme.radiusSmall
                                            color: trow.lvl === "prevent" ? Theme.withAlpha(Theme.error, 0.18)
                                                : trow.lvl === "defer" ? Theme.withAlpha(Theme.warning, 0.18)
                                                : Theme.withAlpha(Theme.success, 0.18)
                                            border { width: 1; color: trow.lvl === "prevent" ? Theme.error
                                                : trow.lvl === "defer" ? Theme.warning
                                                : Theme.success }
                                            Text {
                                                id: lvlText
                                                anchors.centerIn: parent
                                                text: trow.lvl === "unset" ? "allow" : trow.lvl
                                                color: trow.lvl === "prevent" ? Theme.error
                                                    : trow.lvl === "defer" ? Theme.warning
                                                    : Theme.success
                                                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: Font.DemiBold }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: scope.cycleTask(trow.modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                        // -- launches: how firmly the mood refuses media/game.
                        SectionTag { title: "launches" }

                        FieldRow {
                            label: "aggression"
                            options: ["soft", "firm", "hard"]
                            value: scope.launch.aggression || "firm"
                            onPick: (v) => scope.patch({ launches: Object.assign({}, scope.launch, { aggression: v }) })
                        }
                        Text {
                            Layout.fillWidth: true
                            text: (scope.launch.block || []).length === 0
                                ? "refuses nothing"
                                : "refuses: " + (scope.launch.block || []).join(" · ")
                                    + (scope.launch.override ? "  (override available)" : "")
                            color: Theme.subtext
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "aggression \u201csoft\u201d warns and lets through \u00b7 \u201cfirm\u201d/\u201chard\u201d refuse \u00b7 a mood never blocks itself"
                            color: Theme.subtextAlt
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.withAlpha(Theme.border, 0.5) }

                        // -- scenes: which workspace scenes this mood restricts.
                        SectionTag { title: "scenes" }

                        Text {
                            Layout.fillWidth: true
                            text: scope.sceneSummary()
                            color: Theme.subtext
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "absence = reachable; \u201cblocked\u201d only stops dispatch into the scene, never a session already running"
                            color: Theme.subtextAlt
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
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
                        FieldRow {
                            id: paletteField
                            readonly property var raw: (Hyprfocus.current.presentation || {}).palette
                            readonly property bool isPair: raw && typeof raw === "object"
                            label: "lease palette"
                            options: ["none"].concat(Object.keys(Theme.palettes))
                            value: isPair ? (raw.day + " / " + raw.night) : (raw || "none")
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
                            text: "edits apply to " + (scope.mood === "work" ? "the resting mood" : "\u201c" + Focus.current.name + "\u201d") + " \u00b7 persisted to mood-policy.json"
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