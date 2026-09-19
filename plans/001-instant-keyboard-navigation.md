# 001 — No animation on keyboard list navigation

- **Status**: DONE
- **Commit**: n/a (not a git repo)
- **Severity**: HIGH
- **Category**: Purpose & frequency
- **Estimated scope**: 4 files, small

## Problem

Every ⇥ / ↑↓ press animates the selection highlight with a spring (`Motion.selection`,
`spring(duration: 0.26, bounce: 0.14)` plus `matchedGeometryEffect`). The clipboard list also
cross-fades the preview and springs its scroll on every arrow key. That's hundreds of times a day, all
keyboard-initiated, so the rule is no animation. The macOS ⌘⇥ switcher and Raycast both move
their highlight instantly.

- `Sources/Pulse/Switcher/SwitcherModel.swift:59` `withAnimation(Motion.selection) { selection = …; updateViewport() }`
- `Sources/Pulse/Switcher/SwitcherModel.swift:99` `withAnimation(Motion.selection) { selection = index }` (hover)
- `Sources/Pulse/Switcher/SwitcherView.swift:87`, `Sources/Pulse/Clipboard/ClipboardView.swift:142` `.matchedGeometryEffect(id: "selection", …)`
- `Sources/Pulse/Clipboard/ClipboardModel.swift:80,84` `withAnimation(Motion.selection) { selectedID = … }`
- `Sources/Pulse/Clipboard/ClipboardView.swift:100` `withAnimation(Motion.selection) { proxy.scrollTo(id) }`
- `Sources/Pulse/Clipboard/ClipboardView.swift:204` `.transition(.opacity.animation(.easeOut(duration: 0.12)))` on the preview

## Target

- Selection changes are instant: no `withAnimation`, no `matchedGeometryEffect`, no `Namespace`.
- The clipboard preview swaps instantly, and its list scroll is instant, which is native NSTableView behavior.
- One exception: when the **switcher** viewport scrolls (the selection enters the bottom or top third),
  the list slides with `Motion.listScroll = .timingCurve(0.23, 1, 0.32, 1, duration: 0.16)`.
  The reason is spatial: when the whole list shifts under a highlight that stays still, an instant jump reads as
  "the names changed". A 160 ms strong ease-out shows that the list moved.

## Steps

1. Delete `Motion.selection`. Add `Motion.listScroll` (value above).
2. In both models, drop the `withAnimation` wrappers around selection changes.
3. In both views, remove the `@Namespace`, the `namespace` row parameter and `.matchedGeometryEffect`.
4. `SwitcherView` viewport `onChange`: animate with `Motion.listScroll` (nil under Reduce Motion).
5. `ClipboardList` `onChange(of: selectedID)`: plain `proxy.scrollTo(id)`. `ClipboardPreview`: remove the `.transition`.

## Verification

- `make app` builds with no warnings.
- Feel check: hold ⌥ and tap ⇥ quickly six times. The highlight must keep up with every press and never trail behind.
  With more than 6 windows, the list slides by one row when the highlight reaches row 5.
- **Done when**: `grep -rn "Motion.selection\|matchedGeometryEffect" Sources` returns nothing.
