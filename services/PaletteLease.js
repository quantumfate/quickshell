.pragma library

// Resolves a `presentation.palette` lease (LEO-365) against the clock. A
// focus mode's palette is either a plain id (both day and night, the
// backward-compatible form) or a `{ day, night }` pair — so leasing it needs
// the hour to pick a side. Day is 7 <= hour < 19, the same split hypr's
// `,theme.sh` `daytime()` uses, kept in this one place so the shell and the
// compositor never drift on when the sun turns over.

/** True between 07:00 (inclusive) and 19:00 (exclusive). */
function isDaytime(hour) {
    return hour >= 7 && hour < 19;
}

/**
 * The palette name leased at `hour`, or "" for no lease. `palette` is
 * whatever the declaration carries: undefined/null/"" (no lease), a plain id
 * (leased at every hour), or a `{ day, night }` pair (leased per `hour`).
 */
function leasedPalette(palette, hour) {
    if (!palette) return "";
    if (typeof palette === "string") return palette;
    const side = isDaytime(hour) ? palette.day : palette.night;
    return side || "";
}
