// Auto-swap detector control: calibrate the name-pill region, and start/stop the
// `dofus_swap.py` turn detector. Per-character hash capture lives on each chip
// (the ◎ button); this is the global rig.
import QtQuick
import "../../services"   // DofusSwap, Theme

// A plain Row (not RowLayout) — a RowLayout nested in the bar's RowLayout
// collapses to zero width, making the buttons unclickable.
Row {
    id: root
    spacing: 4

    // Screen this control is on — routes its tooltips to the right TipLayer.
    property string screenName: ""

    // Pick the region dofus_swap watches for the turn-start name pill.
    Pill {
        symbol: "⊹"
        // Color-only feedback: accent while picking, warning if uncalibrated.
        tint: DofusSwap.calibrating ? Theme.accent : DofusSwap.calibrated ? Theme.subtext : Theme.warning
        tip: DofusSwap.calibrated
            ? "Recalibrate the turn-popup region (invalidates learned hashes)"
            : "Not calibrated — click to select the turn-popup name region"
        onActivated: DofusSwap.calibrate()
    }

    // Toggle the detector loop; green while running.
    Pill {
        symbol: DofusSwap.detectorRunning ? "■" : "▶"
        tint: DofusSwap.detectorRunning ? Theme.success : Theme.subtext
        tip: DofusSwap.detectorRunning
            ? "Stop the auto turn-swap detector"
            : "Start the auto turn-swap detector for the active team"
        onActivated: DofusSwap.toggle()
    }

    // A small square icon button with an explanatory hover tip (rendered below).
    component Pill: Rectangle {
        property string symbol
        property color tint: Theme.subtext
        property string tip: ""
        signal activated
        implicitWidth: 20; implicitHeight: 20; radius: Theme.radiusSmall
        color: hover.containsMouse ? Theme.surfaceAlt : Theme.surface
        Text { anchors.centerIn: parent; text: parent.symbol; color: parent.tint; font.pixelSize: 12 }
        MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; onClicked: parent.activated() }
        HoverTip { shown: hover.containsMouse && parent.tip !== ""; text: parent.tip; screenName: root.screenName }
    }
}
