.pragma library

// hypr publishes, per screen, `geometry.areas["<screen>"]`:
//
//   {
//     scene: "code",
//     work:    { top_left, top_right, bottom_left, bottom_right },
//     columns: { "1": { top_left, ... }, "2": { ... } },
//   }
//
// (hypr repo docs/scenes.md "Areas"). A scene may declare where a surface
// goes inside that, the way it declares docks:
//
//   surfaces = { notifications = { of = "column:last", scale = 0.5, align = "right" } }
//
// This module is the pure placement math: an area (four corners), a request
// (of/scale/align/valign) and the surface's own content size go in; a
// monitor-local box comes out. Plain JS, no Quickshell types, so
// `node --test` covers every case without a running shell — mirrors
// services/DockPlacement.js.

/**
 * A box's width/height from its corners (`hypr/lib/area.lua`'s `M.corners`).
 * @param {{top_left:{x:number,y:number}, bottom_right:{x:number,y:number}}} corners
 * @returns {{x:number,y:number,width:number,height:number}}
 */
function boxOf(corners) {
  const { top_left: tl, bottom_right: br } = corners;
  return { x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y };
}

/**
 * Resolve `of` against one screen's published `areas` entry.
 *
 * `column:first`/`column:last` pick by numeric order among the declared
 * columns; an unknown or missing column (including "first"/"last" when
 * there are no columns at all) falls back to `work`. A missing `areasForMonitor`
 * (the monitor has not published yet) answers null, so the caller falls back
 * to its own monitor-frame default rather than guessing at a work box.
 *
 * @param {{work: object, columns?: Object<string, object>}|null|undefined} areasForMonitor
 * @param {string} of "work" | "column:<order>" | "column:first" | "column:last"
 * @returns {{x:number,y:number,width:number,height:number}|null}
 */
function resolveArea(areasForMonitor, of) {
  if (!areasForMonitor || !areasForMonitor.work) return null;
  const work = boxOf(areasForMonitor.work);
  if (of === "work" || typeof of !== "string") return work;

  const match = of.match(/^column:(.+)$/);
  if (!match) return work;
  const columns = areasForMonitor.columns || {};
  const orders = Object.keys(columns)
    .map(Number)
    .filter((n) => Number.isFinite(n))
    .sort((a, b) => a - b);
  if (orders.length === 0) return work;

  let key = match[1];
  if (key === "first") key = String(orders[0]);
  else if (key === "last") key = String(orders[orders.length - 1]);

  const column = columns[key];
  return column ? boxOf(column) : work;
}

/**
 * The fallback area for a screen with no published `areas` entry yet (shell
 * start, a workspace between scenes): the monitor less the bar's reserved
 * strip and its resting inset — the same rule a resting bar isle uses
 * (`BarGaps.insetFor`), so a surface can never overlap a bar even before
 * hypr's first publish.
 *
 * @param {{width:number,height:number}} screenSize
 * @param {number} barReserved px reserved at the top for the bar (`Theme.barReserved`)
 * @param {{left:number,right:number}} inset the monitor's resting side inset
 * @returns {{x:number,y:number,width:number,height:number}}
 */
function restingArea(screenSize, barReserved, inset) {
  return {
    x: inset.left,
    y: barReserved,
    width: Math.max(0, screenSize.width - inset.left - inset.right),
    height: Math.max(0, screenSize.height - barReserved),
  };
}

/**
 * Compute a surface's box inside `area`, per its placement request and its
 * own content size.
 *
 * `scale` is the fraction (0–1] of the area's width the surface's WIDTH
 * targets; the surface never shrinks below its content width, so the
 * effective width is `max(scale * area.width, content.width)`, capped at
 * the area's width. Height is always the content's own height, capped at
 * the area's height. Whenever a cap actually shrank a dimension, `warn` is
 * called once with a message naming the surface, the area, and the overflow
 * in px — the box returned is still the capped one, so nothing is ever
 * drawn outside its area.
 *
 * @param {{x:number,y:number,width:number,height:number}} area monitor-local
 * @param {{align?: "left"|"right"|"center", valign?: "top"|"bottom"|"center", scale?: number}} request
 * @param {{width:number,height:number}} content the surface's own implicit/minimum size
 * @param {(msg: string) => void} [warn]
 * @param {string} [surfaceName] for the warning message only
 * @returns {{x:number,y:number,width:number,height:number}}
 */
function place(area, request, content, warn, surfaceName) {
  const noop = () => {};
  const say = typeof warn === "function" ? warn : noop;
  const name = surfaceName || "surface";
  const scale = typeof request.scale === "number" && request.scale > 0 ? Math.min(request.scale, 1) : 1;

  const wantedWidth = Math.max(scale * area.width, content.width);
  const width = Math.min(wantedWidth, area.width);
  if (wantedWidth > area.width) {
    say(`${name}: capped width by ${Math.round(wantedWidth - area.width)}px to fit its area`);
  }

  const height = Math.min(content.height, area.height);
  if (content.height > area.height) {
    say(`${name}: capped height by ${Math.round(content.height - area.height)}px to fit its area`);
  }

  const align = request.align || "left";
  const x = align === "right" ? area.x + area.width - width : align === "center" ? area.x + (area.width - width) / 2 : area.x;

  const valign = request.valign || "top";
  const y =
    valign === "bottom" ? area.y + area.height - height : valign === "center" ? area.y + (area.height - height) / 2 : area.y;

  return { x, y, width, height };
}
