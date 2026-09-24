# Mode transition veil

`TransitionOverlay.qml` draws the full-screen scrim that hides the desk while a
hyprfocus mode is being applied (LEO-423). It reads the shared
`hyprfocus.transition` store that the compositor's `hypr/lib/transition.lua`
publishes, so the shell and the compositor agree on when the veil is up, which
mode it is for, and how long it should stay.

The module is imported as a directory in `shell.qml`:

```qml
import "modules/transition"
```

A `qmldir` exposes `TransitionOverlay` explicitly so the type resolves the same
way whether Quickshell is running from the working tree or an installed layout.

## Mapped for the whole session

The overlay's layer surfaces never unmap. Verified live on the running desk:
a layer surface that unmaps at one settle and remaps for the next transition
commits exactly one frame after remapping and then never renders again, so any
state the first frame did not carry never appears. A permanently mapped surface
keeps its render loop; while idle it is fully transparent (`color:
"transparent"`), takes no keyboard (`WlrKeyboardFocus.None`) and its input mask
is empty, so it is invisible to both the eye and the pointer.

The show/hide is a snap, not a fade. The compositor suspends its animations for
the whole apply, so there is no continuous desk to fade against, and the
earlier Behavior-driven fades could leave the content at a stuck partial
opacity across brackets. The label is static by the same live finding that
motivates the permanent mapping: a covered desk produces no compositor damage,
so timer-driven updates (a countdown, a progress line) are not guaranteed to
render mid-bracket — a frozen countdown would read as exactly the stuck
transition it was meant to expose, so the veil carries the mode label only.

## Watchdog

If the compositor's own failsafe cannot settle a bracket (the store write never
lands), the overlay force-hides locally ~4.5 s after the published
`duration_ms`. The timer is armed fresh on every `active` flip and cancelled by
a normal settle, so no state is carried across brackets.
