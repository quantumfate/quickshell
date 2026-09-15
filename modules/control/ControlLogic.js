.pragma library
// Pure logic for the Control Centre: wallpaper listing and the numeric clamps
// used by the scale/transparency sliders. Kept separate from ControlPanel.qml
// so it's covered by tests/controllogic.test.js without a live Store or Process.

var IMAGE_EXTS = [".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif"];

// `ls` output (one path per line, possibly with a trailing blank line or an
// `ls: cannot access` stderr line if the directory is missing) -> sorted
// filenames, image files only.
function parseWallpaperList(text) {
    return (text || "")
        .split("\n")
        .map(function (s) { return s.trim(); })
        .filter(function (s) { return s.length > 0 && s.indexOf(":") === -1; })
        .filter(function (p) {
            var lower = p.toLowerCase();
            return IMAGE_EXTS.some(function (ext) { return lower.endsWith(ext); });
        })
        .map(function (p) { return p.split("/").pop(); })
        .sort(function (a, b) { return a.localeCompare(b); });
}

function clamp(value, lo, hi) {
    return Math.max(lo, Math.min(hi, value));
}

// Scale/transparency sliders drag in [0,1] fraction of their track; map that
// to the real dial range and back, matching Theme's own clamp (services/Theme.qml).
function scaleFromFraction(fraction) {
    return clamp(0.8 + fraction * (2.5 - 0.8), 0.8, 2.5);
}
function fractionFromScale(scale) {
    return clamp((scale - 0.8) / (2.5 - 0.8), 0, 1);
}
function transparencyFromFraction(fraction) {
    return clamp(fraction, 0, 1);
}

// h/j/k/l movement over a fixed-width grid of `count` items, wrapping on every
// edge so the keyboard picker never dead-ends at a corner. `key` is one of
// "h", "j", "k", "l"; any other key is a no-op (returns the same index).
function moveGridIndex(index, key, count, columns) {
    if (count <= 0) return index;
    var rows = Math.ceil(count / columns);
    var row = Math.floor(index / columns);
    var col = index % columns;
    function at(r, c) {
        var wrappedRow = ((r % rows) + rows) % rows;
        var wrappedCol = ((c % columns) + columns) % columns;
        var i = wrappedRow * columns + wrappedCol;
        return i < count ? i : index;
    }
    switch (key) {
        case "h": return at(row, col - 1);
        case "l": return at(row, col + 1);
        case "k": return at(row - 1, col);
        case "j": return at(row + 1, col);
        default: return index;
    }
}

/**
 * The selected row index moves with the keyboard (LEO-226 / LEO-244's
 * keyboard parity): up/down move one row and clamp (a list is not a grid
 * grid loop — the first and last entries do not wrap into each other);
 * `pick` resets to the top. `index` returns reference: pass the moved
 * value back down so restarts can find their row.
 */
function moveSelectionIndex(index, key, count) {
    if (count <= 0) return 0;
    var next = index;
    if (key === "down" || key === "tab") next = index + 1;
    else if (key === "up" || key === "backtab") next = index - 1;
    next = clamp(next, 0, count - 1);
    return next;
}
