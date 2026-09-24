// NotifyPlacement.js — where the toast stack stands (LEO-424).
//
// The mood policy names a position; this resolves it to the two anchors the
// toast surface needs. Kept as a `.pragma library` so the mapping is testable
// from node while the QML stays a thin renderer, and so an unknown value from
// an edited store degrades to the default instead of parking the stack
// off-screen or at a null anchor.
.pragma library

// vertical edge + horizontal alignment, spelled the way the mood policy does.
var POSITIONS = {
    "top-left": { v: "top", h: "left" },
    "top-center": { v: "top", h: "center" },
    "top-right": { v: "top", h: "right" },
    "bottom-left": { v: "bottom", h: "left" },
    "bottom-center": { v: "bottom", h: "center" },
    "bottom-right": { v: "bottom", h: "right" }
};

// Top-centre under the bar: symmetric on a wide desk and clear of the right
// edge where browsers live. The mood may override it.
var DEFAULT = "top-center";

/** The anchor pair for a position name, falling back to the default. */
function resolve(position) {
    return POSITIONS[position] || POSITIONS[DEFAULT];
}

/** Whether a store value is one this resolver knows. */
function known(position) {
    return Object.prototype.hasOwnProperty.call(POSITIONS, position);
}

/** Every position the policy may name, for the schema and tests to agree on. */
function names() {
    return Object.keys(POSITIONS);
}
