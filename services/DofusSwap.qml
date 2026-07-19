pragma Singleton
// DofusSwap — the bridge to the `dofus_swap.py` auto-turn-swap detector.
//
// That script owns ~/.config/dofus-swap.json (a `region` + per-character phash
// `hashes`) and is the ONLY writer — the UI never edits the file directly, it
// shells the script's own subcommands. This keeps a single writer (no racing
// double-writes) and reuses the phash logic that only Python/PIL can do.
//
// We reflect the config read-only so the taskbar can show which characters are
// calibrated, and expose:
//   calibrate()        pick the name-pill region (slurp, one-time per res)
//   learn(name)        grab the region NOW + store its hash under `name`
//                      (press while that character's turn popup is on screen)
//   run(names)/stop()  start/stop the detector loop for a roster
//
// The join to team.json is the character name itself (the script lowercases it),
// so no extra state has to be kept in sync.
import Quickshell
import Quickshell.Io
import QtQuick
import "."   // Notify singleton

Singleton {
    id: root

    readonly property string configPath: Quickshell.env("HOME") + "/.config/dofus-swap.json"

    // Reflected config (external file, written only by dofus_swap.py).
    property var region: undefined            // { left, top, width, height } | undefined
    property var hashes: ({})                 // lowercased-name -> phash hex

    readonly property bool calibrated: region !== undefined

    // True once a reference hash exists for this character (case-insensitive).
    function learned(name) { return root.hashes[(name || "").toLowerCase()] !== undefined; }

    FileView {
        id: cfg
        path: root.configPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(cfg.text() || "{}");
                root.region = d.region;
                root.hashes = d.hashes ?? ({});
            } catch (e) { console.warn("DofusSwap: bad config JSON", e); }
        }
        onLoadFailed: { root.region = undefined; root.hashes = ({}); }
    }

    // ---- mutations: delegate to the script, then let watchChanges refresh ----

    // True while the slurp region-picker is up (drives the button's color).
    // A direct Quickshell Process child gets no new session, and slurp then fails
    // to create its selection surface (invisible picker). So calibrate is spawned
    // fully DETACHED via `setsid … &` — the picker renders — which means the
    // launcher Process exits immediately; the detached script reports the real
    // result back through the `_calDone` IPC (see below), which clears this flag.
    property bool calibrating: false

    // Detached picker; on finish it calls back so we can notify + refresh.
    Process {
        id: calibrateProc
        command: ["bash", "-lc",
            "setsid bash -c 'dofus_swap.py calibrate "
            + "&& qs -c quantumfate ipc call dofusSwap _calDone ok "
            + "|| qs -c quantumfate ipc call dofusSwap _calDone cancel' "
            + ">/dev/null 2>&1 </dev/null &"]
    }
    function calibrate() {
        if (root.calibrating) return;   // a picker is already open
        root.calibrating = true;
        calibrateProc.running = true;   // launches detached, exits immediately
    }
    // Called by the detached picker when it finishes (ok = region saved).
    function _calDone(ok) {
        root.calibrating = false;
        cfg.reload();
        ok ? Notify.send("Recalibrated", "turn-popup region set", "success")
           : Notify.send("Calibration cancelled", "", "error");
    }

    // Capture the current region and store it as `name`'s reference hash. The
    // caller times this to a visible turn-start popup ("screenshot on demand").
    // `capturing` + `captured` let the UI show live feedback that it happened.
    property string capturing: ""              // name mid-capture, "" when idle
    signal captured(string name, bool ok)      // fired when a learn finishes

    Process {
        id: learnProc
        onExited: (code, status) => {
            const name = root.capturing;
            root.captured(name, code === 0);
            root.capturing = "";
            cfg.reload();   // pick up the new hash -> dot turns green
            code === 0
                ? Notify.send("Captured " + name, "turn-hash stored", "success")
                : Notify.send("Capture failed", name + " — popup visible?", "error");
        }
    }
    function learn(name) {
        if (learnProc.running || !name) return;
        root.capturing = name;
        learnProc.command = ["dofus_swap.py", "learn", name];
        learnProc.running = true;
    }

    // ---- detector loop -------------------------------------------------------
    //
    // The detector is a detached process (setsid), NOT a quickshell child, so it
    // survives a shell reload and can be toggled identically from the Hyprland
    // `s` key (hypr/services/dofus/swap.lua). Both sides converge on one process
    // matched by `pgrep`, so `detectorRunning` is accurate whoever started it.
    // The script reads its roster live from team.json — no characters passed.

    property bool detectorRunning: false
    // Escaped dot (matches hypr swap.lua): the regex `dofus_swap\.py run` matches
    // the real detector's cmdline, but NOT this probe's own cmdline (which carries
    // the literal backslash), so we don't count ourselves as "running".
    readonly property string _pgrep: "dofus_swap\\.py run"

    // Poll the real process state so external start/stop (hypr) is reflected.
    Process {
        id: probe
        command: ["bash", "-lc", "pgrep -f '" + root._pgrep + "' >/dev/null && echo 1 || echo 0"]
        stdout: StdioCollector { onStreamFinished: root.detectorRunning = (this.text || "").trim() === "1" }
    }
    Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!probe.running) probe.running = true }

    Process { id: starter }
    function run() {
        if (root.detectorRunning) return;
        const log = (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/dofus_swap.log";
        starter.command = ["bash", "-lc", "setsid dofus_swap.py run >> '" + log + "' 2>&1 </dev/null &"];
        starter.running = true;
    }
    Process { id: stopper }
    function stop() { stopper.command = ["pkill", "-f", root._pgrep]; stopper.running = true; }
    function toggle() { root.detectorRunning ? stop() : run(); }

    // ---- scripting surface: qs -c quantumfate ipc call dofusSwap <fn> -------
    IpcHandler {
        target: "dofusSwap"
        function calibrate(): void { root.calibrate(); }
        // Callback from the detached picker: "ok" saved a region, else cancelled.
        function _calDone(result: string): void { root._calDone(result === "ok"); }
        function learn(name: string): void { root.learn(name); }
        function run(): void { root.run(); }
        function stop(): void { root.stop(); }
        function toggle(): void { root.toggle(); }
        function status(): string {
            return (root.detectorRunning ? "running" : "stopped")
                + " calibrated=" + root.calibrated
                + " learned=" + Object.keys(root.hashes).join(",");
        }
    }
}
