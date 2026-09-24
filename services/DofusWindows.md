# DofusWindows

The live view of the Dofus group: which clients exist, in group order, and which
one is the active tab. [`DofusState`](DofusState.qml) owns the _order_
(`dofus/team.json`); this service owns the _windows_, and never stores a window
id in state.

The bar's Dofus roster ([`modules/bar/DofusRoster.qml`](../modules/bar/DofusRoster.qml))
and the team panel ([`modules/dofus/TeamSelector.qml`](../modules/dofus/TeamSelector.qml))
both read `DofusWindows.windows`; neither reconstructs membership.

## The published record

`windows` is an array of live `Dofus.x64` clients, in group order, one object
per window: `name`, `title`, `pid`, `address`, `selector`, `focused`,
`grouped`, `at`/`size`, `workspaceAddress`/`workspaceName`/`monitorId`. The
field list lives on the property in the source.

Group order comes from a member's own `grouped` list — the same thing the
compositor's groupbar shows — falling back to report order so the model never
goes empty.

## The snapshot, and the one thing that does not wait for it

The list is a snapshot from `hyprctl clients -j`: a slow poll, plus a short
debounce over the compositor's _structural_ events (open/close/title/move).
Requests that arrive while a fetch is in flight coalesce into exactly one extra
fetch.

**Focus is the exception.** `activewindowv2` carries the active window's
address directly, so it is applied to the published list on the spot — the
roster's highlight is one event hop away instead of one poll.

Which member that marks is [`DofusFocus.js`](DofusFocus.js)'s rule, and it is
pure so `tests/dofusfocus.test.js` covers it without a shell:

- `focusHistoryID` **0 is the most recently focused** window and higher is
  older. Reading the highest id — as this service used to — picks the _least_
  recently focused member, which is why the highlight sat on the wrong client.
- A focused member is the active tab; while the group is unfocused (another app
  on the same workspace) the last member that held focus stands in, which is
  what the compositor's groupbar does; and a group nothing has focused still
  reads as one group.

The list is published only when it actually changed. Replacing the array
re-creates every Repeater delegate in the roster, which re-lays-out the strip
and drops hover/focus state — so a poll that learned nothing new is invisible.

## Actions

`focus(selector)` (delegated to [`Hypr`](Hypr.qml)), `setName`/`clearName`
(retitle a client so it joins or leaves a character), and `renameCharacter`
(retitle the live window when a character is renamed in state).

## See also

- [`modules/bar/Readme.md`](../modules/bar/Readme.md) — the bar and its isles.
- [`DofusSwap.qml`](DofusSwap.qml) — the swap detector the roster's controls drive.
