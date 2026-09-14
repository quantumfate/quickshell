pragma Singleton
// Sound — rain/lofi ambience over a single long-lived local mpv, driven by
// IPC. Local files, no network: offline, no telemetry, and instant to switch,
// since mpv is already idling between tracks rather than being spawned fresh
// per track. Talks to mpv over its JSON IPC socket (--input-ipc-server); a
// python3 one-liner is the client (already a build dependency here — see
// dofus_swap.py — so this adds none) rather than a Process per keystroke.
//
// Deliberately not mode-gated: rain while working is the point of ambience,
// and a second gate channel would have to ride the contract's task map
// (LEO-252/271) rather than grow here. Ambient audio is something the user
// starts and stops, not something the desk polices.
import Quickshell
import Quickshell.Io
import QtQuick
import "."   // Config, Notify singletons

Singleton {
    id: root

    Store {
        id: store
        name: "sound"
        defaults: ({
            mode: "off", track: null, volume: 0.5,
            // The pools are declared data, edited like everything else in the
            // store — "$HOME/..." is resolved below, because JSON cannot
            // expand environment. The keys must be the schema's mode enum
            // minus "off"; sound.test.js pins that lockstep.
            pools: { rain: "$HOME/Music/ambient/rain", lofi: "$HOME/Music/ambient/lofi" },
        })
    }

    readonly property string mode: store.get("mode") ?? "off"
    readonly property var track: store.get("track") ?? null
    readonly property real volume: store.get("volume") ?? 0.5

    readonly property string socketPath: Config.stateDir + "/sound.mpv.sock"
    readonly property var dirs: {
        const pools = store.get("pools") ?? {};
        const home = Quickshell.env("HOME");
        const out = {};
        for (const kind in pools) out[kind] = pools[kind].replace("$HOME", home);
        return out;
    }

    // ---- mpv lifecycle --------------------------------------------------
    //
    // mpv can die (OOM kill, crash, `pkill mpv` from somewhere else); every
    // entry point below goes through _ensureAlive() first rather than trusting
    // a cached "it's running" flag, so a dead mpv self-heals on the next
    // command instead of eating it silently.

    property bool mpvAlive: false

    Process {
        id: probe
        command: ["bash", "-lc", "pgrep -f 'input-ipc-server=" + root.socketPath + "' >/dev/null && echo 1 || echo 0"]
        stdout: StdioCollector { onStreamFinished: root.mpvAlive = (this.text || "").trim() === "1" }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!probe.running) probe.running = true }

    Process { id: spawner }
    function _spawn() {
        // `--loop-file=inf` is the player loop: ambient audio is written to
        // sound continuous, and a track ending into mpv's idle would read as
        // a broken player rather than a finished track. Moving between tracks
        // stays manual (`sound next`) — a playlist that can't be stopped is
        // not ambience.
        spawner.command = ["bash", "-lc",
            "rm -f '" + root.socketPath + "'; setsid mpv --idle --no-video --no-terminal --loop-file=inf " +
            "--input-ipc-server='" + root.socketPath + "' --volume=" + Math.round(root.volume * 100) +
            " >/dev/null 2>&1 </dev/null &"];
        spawner.running = true;
        root.mpvAlive = true; // optimistic; the probe corrects this within 2s if the spawn failed
    }
    function _ensureAlive() { if (!root.mpvAlive) root._spawn(); }

    // One-shot writer per command. mpv's socket takes concurrent clients fine,
    // and IPC calls here are rare next to how often a per-track process used
    // to spawn. Retries briefly: right after _spawn() the socket file may not
    // exist yet.
    Process { id: sender }
    function _send(obj) {
        root._ensureAlive();
        const payload = JSON.stringify(obj);
        sender.command = ["python3", "-c",
            "import socket,sys,time\n" +
            "path, msg = sys.argv[1], sys.argv[2]\n" +
            "for _ in range(25):\n" +
            "    try:\n" +
            "        s = socket.socket(socket.AF_UNIX)\n" +
            "        s.connect(path)\n" +
            "        s.sendall((msg + '\\n').encode())\n" +
            "        s.close()\n" +
            "        break\n" +
            "    except OSError:\n" +
            "        time.sleep(0.2)\n",
            root.socketPath, payload];
        sender.running = true;
    }

    // ---- library: pick a file out of a local playlist directory ----------

    Process {
        id: lister
        property string pendingKind: ""
        property string pendingTrack: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const files = (this.text || "").split("\n").map(s => s.trim()).filter(Boolean);
                if (files.length === 0) {
                    Notify.send("Sound", "no tracks in " + lister.pendingKind, "error");
                    return;
                }
                const wanted = lister.pendingTrack;
                const file = wanted ? (files.find(f => f.endsWith(wanted)) || files[0])
                                     : files[Math.floor(Math.random() * files.length)];
                root._loadFile(lister.pendingKind, file);
            }
        }
    }
    function _browse(kind, wantedTrack) {
        const dir = root.dirs[kind];
        if (!dir) return;
        lister.pendingKind = kind;
        lister.pendingTrack = wantedTrack || "";
        lister.command = ["bash", "-lc", "ls -1 '" + dir + "'/*.* 2>/dev/null"];
        lister.running = true;
    }
    function _loadFile(kind, file) {
        root._send({ command: ["loadfile", file] });
        root._send({ command: ["set_property", "volume", Math.round(root.volume * 100)] });
        store.set({ mode: kind, track: file });
    }

    // ---- public transport --------------------------------------------------

    ///Play a random track from `kind`'s playlist ("rain" | "lofi").
    function play(kind) { root._browse(kind, ""); }

    ///Play a specific track (matched by filename suffix) from `kind`'s playlist.
    function pickTrack(kind, name) { root._browse(kind, name); }

    ///Next random track in the current playlist; no-op while stopped.
    function next() { if (root.mode !== "off") root._browse(root.mode, ""); }

    function stop() {
        root._send({ command: ["stop"] });
        store.set({ mode: "off", track: null });
    }

    function setVolume(v) {
        const vol = Math.max(0, Math.min(1, v));
        root._send({ command: ["set_property", "volume", Math.round(vol * 100)] });
        store.set({ volume: vol });
    }

    // ipc: qs -c quantumfate ipc call sound <fn>
    IpcHandler {
        target: "sound"
        function play(kind: string): void { root.play(kind); }
        function pick(kind: string, track: string): void { root.pickTrack(kind, track); }
        function next(): void { root.next(); }
        function stop(): void { root.stop(); }
        function volume(value: real): void { root.setVolume(value); }
        function status(): string {
            return root.mode + (root.track ? (" — " + root.track) : "") + " (vol " + root.volume + ")";
        }
        function reload(): void { store.reload(); }
    }
}
