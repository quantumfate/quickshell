.pragma library

// LEO-420: pure placement math for a docked bar isle. hypr publishes, per
// screen and isle id, a document under the `geometry` store's `docks` key:
//
//   geometry.docks["DP-1"]["bar.workspaces"] = {
//     region: { x, y, w, h },   // monitor-local gutter the isle may occupy
//     anchor: { x, y },         // the point the isle's growth corner aligns to
//     grow:   "up"|"down"|"left"|"right",  // away from the window
//     align:  "start"|"center"|"end",      // which part of the isle the anchor is
//     orientation: "horizontal"|"vertical",
//     state:  "docked"|"fallback"|"resting",
//   }
//
// This module never touches the store or Quickshell types — it is plain JS so
// `node --test` can exercise every anchor/grow/clamp case without a running
// shell. Bar.qml is the only caller; it feeds real isle sizes and screen
// bounds and applies the returned rect.

/**
 * The growth-corner rect for an isle of the given size against a dock
 * document's anchor + grow + align, with NO clamping applied yet.
 *
 * `grow` settles the axis the isle extends along: the anchor is the edge it
 * touches, and the isle runs away from it. `align` settles the OTHER axis —
 * the one running along the gutter — by saying which part of the isle the
 * anchor point is: its start, its middle, or its end. A top gutter takes all
 * three (`top-left`, `top-center`, `top-right`), and reading every anchor as
 * a start (what this did before align was published) put a right-aligned
 * isle's LEFT edge on the window's right edge, one isle-width too far out,
 * where the bounds clamp then flattened it against the screen edge.
 *
 * @param {{x:number,y:number}} anchor
 * @param {"up"|"down"|"left"|"right"} grow
 * @param {number} width
 * @param {number} height
 * @param {"start"|"center"|"end"} [align] defaults to "start" (pre-align docs)
 * @returns {{x:number,y:number}}
 */
function rawRect(anchor, grow, width, height, align) {
  const vertical = grow === "up" || grow === "down";
  const along = vertical ? width : height;
  const shift = align === "end" ? -along : align === "center" ? -along / 2 : 0;

  const x = vertical ? anchor.x + shift : grow === "left" ? anchor.x - width : anchor.x;
  const y = vertical ? (grow === "up" ? anchor.y - height : anchor.y) : anchor.y + shift;
  return { x: x, y: y };
}

/**
 * Place an isle per its published dock document.
 *
 * Clamp rule (LEO-420 §4): an isle larger than its region forfeits the
 * surplus — it is pushed toward the screen edge the gutter faces, then
 * clamped inside the screen bounds. `clamped` is true whenever either step
 * moved the isle off the raw anchor placement, so the caller can warn once
 * per state change rather than per frame.
 *
 * `edgeMargin` is how far the isle floats clear of the edge it stands on —
 * the bar's own styling, not the desk's geometry, and the same margin a
 * resting isle keeps. It is added or subtracted on the GROWTH axis alone,
 * by the sign of `grow`; the along-edge axis stays where the scene's
 * alignment put it.
 *
 * @param {object} dock the per-screen, per-isle dock document (region/anchor/grow)
 * @param {{width:number,height:number}} isleSize the isle's own natural size
 * @param {{width:number,height:number}} screenSize the monitor's size
 * @param {number} [edgeMargin] clearance from the edge the isle stands on
 * @returns {{x:number,y:number,clamped:boolean}|null} null when the document
 *   carries no geometry to place by
 */
function placeDock(dock, isleSize, screenSize, edgeMargin) {
  // A document with no geometry is not placeable: `hidden` and `resting` both
  // publish a bare state, and a scene can change under a live read. Answer
  // null rather than reading `anchor.x` off undefined — the caller already
  // treats null as "stay resting".
  if (!dock || !dock.anchor || !dock.region) return null;
  const finite = (value) => typeof value === "number" && Number.isFinite(value);
  const numbers = [
    dock.anchor.x, dock.anchor.y, dock.region.x, dock.region.y,
    dock.region.w, dock.region.h, isleSize.width, isleSize.height,
    screenSize.width, screenSize.height,
  ];
  // A hook can publish a half-built geometry document while a monitor or an
  // empty scene is settling. Never turn that document into an off-screen Item.
  if (numbers.some((value) => !finite(value))
      || isleSize.width <= 0 || isleSize.height <= 0
      || screenSize.width <= 0 || screenSize.height <= 0) return null;

  const region = dock.region;
  const margin = edgeMargin || 0;
  const rect = rawRect(dock.anchor, dock.grow, isleSize.width, isleSize.height, dock.align);
  if (dock.grow === "down") rect.y += margin;
  else if (dock.grow === "up") rect.y -= margin;
  else if (dock.grow === "right") rect.x += margin;
  else if (dock.grow === "left") rect.x -= margin;

  // Overflow is per axis, and only the growth axis gives way. An isle taller
  // than its gutter still starts where the anchor says along the edge —
  // centring both axes (what this did first) slid every isle into the middle
  // of the window it was supposed to hang off the corner of.
  const vertical = dock.grow === "up" || dock.grow === "down";

  // The growth axis is bounded by the gutter first, so an isle never covers
  // the window it hangs from. The final screen clamp below is a second guard:
  // a narrow empty-scene gutter must not leave a bar outside the output.
  //
  // Which end of the region the window sits at follows from the EDGE, not
  // from `grow`: a window dock hugs its target and grows away from it, while
  // a `screen` dock stands on the monitor's edge and grows inward — opposite
  // directions in the same gutter. A top or left gutter has the window at
  // the region's far end; a bottom or right gutter has it at the start.
  // A document published before `edge` existed is read the old way, by
  // `grow` alone — correct for every dock the inward model produced.
  const start = vertical ? region.y : region.x;
  const extent = vertical ? region.h : region.w;
  const size = vertical ? isleSize.height : isleSize.width;
  const towardEnd = dock.edge
    ? dock.edge === "top" || dock.edge === "left"
    : dock.grow === "down" || dock.grow === "right";
  const raw = vertical ? rect.y : rect.x;

  let along = raw;
  if (size <= extent) {
    along = Math.min(Math.max(raw, start), start + extent - size);
  } else {
    // Too big to stand in the gutter: put the edge that faces the window
    // exactly on the boundary and let the rest hang off the screen.
    along = towardEnd ? start + extent - size : start;
  }

  // The along-edge axis is the scene's declared alignment; it is bounded by
  // the screen so an isle can still run the length of the gutter.
  const acrossMax = vertical
    ? Math.max(0, screenSize.width - isleSize.width)
    : Math.max(0, screenSize.height - isleSize.height);
  const across = Math.min(Math.max(vertical ? rect.x : rect.y, 0), acrossMax);

  const rawX = vertical ? across : along;
  const rawY = vertical ? along : across;
  const x = Math.min(Math.max(rawX, 0), Math.max(0, screenSize.width - isleSize.width));
  const y = Math.min(Math.max(rawY, 0), Math.max(0, screenSize.height - isleSize.height));

  return {
    x: x,
    y: y,
    clamped: size > extent || x !== rect.x || y !== rect.y,
  };
}

/**
 * Whether a clamp warning should fire now: exactly on the false->true edge,
 * never while already clamped and never on recovery. Caller keeps the
 * previous `clamped` value per isle id and calls this before updating it.
 *
 * @param {boolean} wasClamped
 * @param {boolean} isClamped
 * @returns {boolean}
 */
function shouldWarnClamp(wasClamped, isClamped) {
  return !wasClamped && isClamped;
}

/**
 * Whether a mode carries geometry to place the isle by. The two resolved
 * states do; "resting" and "hidden" do not.
 *
 * @param {string} mode
 * @returns {boolean}
 */
function isPlaced(mode) {
  return mode === "docked" || mode === "fallback";
}

/**
 * Resolve which dock document (if any) applies, and what visual state the
 * isle should render.
 *
 * - No published dock for this screen/isle -> "resting" for the three isles
 *   every bar has (ALWAYS below), "hidden" for a scene-owned widget: those
 *   are opt-in, named by the scene that wants them.
 * - `dock === false` -> "hidden": the isle draws nothing.
 * - dock.state "docked" -> placed per placeDock.
 * - dock.state "fallback" -> ALSO placed per placeDock. "fallback" is the
 *   publisher's word for "resolved, but down the ladder" (the declared
 *   fallback spec, or the implicit same-anchor-on-screen rung) -- it carries
 *   a full region/anchor/grow exactly like "docked" does. Reading it as
 *   "freeze where you were" threw that geometry away, which is why an isle
 *   that stepped down never moved: every scene puts two isles on one block's
 *   top gutter, so one of them is always the fallback. The distinction
 *   survives for styling and telemetry, not for placement.
 * - dock.state "resting" -> today's static layout, same as no document.
 *
 * @param {object|null|undefined} docksForScreen geometry.docks[screenName]
 * @param {string} isleId
 * @returns {"resting"|"hidden"|"docked"|"fallback"} the mode Bar.qml should render
 */
// The isles a bar always has, wherever it stands. Everything else is a
// SCENE-OWNED widget: it appears only where a scene's `docks` map names it,
// with an anchor. A scene that says nothing about the tab strip or the Dofus
// roster does not get one -- opt-in, so a scene has explicit control over
// what it puts on its screen rather than inheriting whatever the shell
// decided to draw from what happened to be focused.
const ALWAYS = ["bar.workspaces", "bar.center", "bar.clock"];

function resolveDockMode(docksForScreen, isleId) {
  // NO MAP AT ALL is not a scene saying no: it is a screen the desk has not
  // published for yet (a shell that just started, a monitor mid-hotplug, a
  // pass whose docks were swept). Reading it as "no" hid every scene-owned
  // isle on a scene that declares it -- the tab strip vanished from the code
  // deck for the life of the shell. Opt-in is decided by a map that EXISTS
  // and does not name the isle; without a map, every isle rests.
  if (!docksForScreen) return "resting";
  const dock = docksForScreen[isleId];
  if (dock === undefined) return ALWAYS.indexOf(isleId) === -1 ? "hidden" : "resting";
  if (dock === false) return "hidden";
  if (dock.state === "docked") return "docked";
  if (dock.state === "fallback") return "fallback";
  return "resting";
}
