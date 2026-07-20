// Weather — condition glyph + temperature from wttr.in (geo-IP located). Polled
// on a long interval since it's a network call; click opens the full forecast.
// Blank until the first successful fetch, and whenever the network is down.
import QtQuick
import "../../services"   // Theme
PollText {
    color: Theme.c.sky
    // %c = condition emoji, %t = temperature; strip the leading '+' wttr adds.
    command: "curl -sf --max-time 10 'https://wttr.in/?format=%c+%t' 2>/dev/null | tr -d '+' | grep . || true"
    clickCommand: "xdg-open 'https://wttr.in' >/dev/null 2>&1"
    intervalMs: 900000   // 15 min — weather doesn't move faster than that
}
