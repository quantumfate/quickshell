.pragma library

// DofusFocus — the pure half of DofusWindows' focus resolution.
//
// Kept out of the singleton so the one thing that was actually wrong here can
// be exercised against real `hyprctl clients -j` shapes: which member of the
// Dofus group is the active tab.
//
// `focusHistoryID` 0 is the MOST recently focused window and higher is older
// (Hyprland's own ordering — the active window always reads 0 in
// `hyprctl clients -j`). DofusWindows used to take the HIGHEST id among the
// group, which is the LEAST recently focused member, so the roster's highlight
// sat on the wrong client almost every time; the rare case where it looked
// right was a group no member had been focused twice in.
//
// This module never touches the store or Quickshell types — it is plain JS so
// `node --test` can cover the resolution without a running shell. DofusWindows
// is the only caller.

/**
 * Normalise a Hyprland address for comparison.
 *
 * `hyprctl clients -j` reports `"0x55a9…"`; the `activewindowv2` raw event
 * reports the same address with no `0x` prefix. Both are lowercase, but the
 * comparison is case-folded anyway so an address that ever arrives uppercase
 * cannot silently stop matching.
 */
function normalize(address) {
    if (!address) return "";
    const s = String(address).trim().toLowerCase();
    return s.startsWith("0x") ? s : ("0x" + s);
}

/**
 * The address of the window the compositor says is active, read from a
 * `hyprctl clients -j` snapshot's own focus history. Returns "" when the
 * snapshot carries no usable history.
 *
 * This is the SEED only: a live `activewindowv2` event is the authoritative
 * answer and arrives without waiting for a poll.
 */
function activeFromHistory(clients) {
    let best = Infinity;
    let address = "";
    for (const c of (clients ?? [])) {
        const id = c?.focusHistoryID ?? -1;
        if (id >= 0 && id < best) { best = id; address = normalize(c?.address); }
    }
    return address;
}

/**
 * The address the roster should mark as the active tab, or "" for none.
 *
 * `active` is the compositor's live focus; `lastDofus` is the last member that
 * held it; `windows` is the published member list. A Dofus window is marked
 * whenever focus is on one. When focus is somewhere else — another app on the
 * same workspace — the strip keeps the last member that held it, which is what
 * the compositor's groupbar does while the group is unfocused; and a group
 * nothing has ever focused still reads as one group rather than none.
 */
function focusedAddress(active, lastDofus, windows) {
    const members = windows ?? [];
    const focused = normalize(active);
    const last = normalize(lastDofus);
    const has = (addr) => addr !== "" && members.some(w => normalize(w.address) === addr);
    if (has(focused)) return focused;
    if (has(last)) return last;
    return members.length > 0 ? normalize(members[0].address) : "";
}
