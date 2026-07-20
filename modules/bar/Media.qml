// Media — now-playing from MPRIS: track title with prev / play-pause / next
// controls. Event-driven off the Mpris service; collapses to nothing when no
// player is present. Prefers a currently-playing player over an idle one.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../../services"   // Theme, Tip

RowLayout {
    id: root

    property string screenName: ""

    // The player we surface: the first one that's playing, else the first at all.
    readonly property var players: Mpris.players?.values ?? []
    readonly property var player: {
        for (const p of players) if (p.isPlaying) return p;
        return players.length > 0 ? players[0] : null;
    }
    visible: player !== null
    spacing: 4

    // A control glyph button; disabled state dims and swallows the click.
    component Ctl: Text {
        property string glyph: ""
        property bool can: true
        signal activated()
        text: glyph
        color: mouse.containsMouse && can ? Theme.c.mauve
             : can ? Theme.text : Theme.overlay
        opacity: can ? 1.0 : 0.5
        font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
        MouseArea {
            id: mouse
            anchors.fill: parent; hoverEnabled: true
            cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (parent.can) parent.activated()
        }
    }

    Ctl {
        glyph: "󰒮"; can: !!root.player?.canGoPrevious
        onActivated: root.player.previous()
    }
    Ctl {
        glyph: root.player?.isPlaying ? "󰏤" : "󰐊"
        can: !!root.player?.canTogglePlaying
        onActivated: root.player.togglePlaying()
    }
    Ctl {
        glyph: "󰒭"; can: !!root.player?.canGoNext
        onActivated: root.player.next()
    }

    Text {
        id: label
        Layout.maximumWidth: 260
        elide: Text.ElideRight
        text: {
            const p = root.player;
            if (!p) return "";
            const title = p.trackTitle || "";
            const artist = p.trackArtist || "";
            return artist && title ? artist + " – " + title : title || artist || p.identity;
        }
        color: Theme.subtext
        font { family: Theme.fontFamily; pixelSize: 12; weight: Theme.barFontWeight }
        verticalAlignment: Text.AlignVCenter

        HoverHandler { id: hover }
        HoverTip {
            shown: hover.hovered; screenName: root.screenName
            text: {
                const p = root.player;
                if (!p) return "";
                const bits = [p.trackTitle, p.trackArtist, p.trackAlbum].filter(x => x);
                return (p.identity ? p.identity + " · " : "") + (bits.join(" — ") || "…");
            }
        }
    }
}
