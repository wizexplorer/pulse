# 004 — Remove double-click disambiguation delay

- **Status**: DONE · **Commit**: n/a · **Severity**: MEDIUM · **Category**: Interruptibility / response

## Problem

`Sources/Pulse/Clipboard/ClipboardView.swift:85-86`:
```swift
.onTapGesture(count: 2) { model.select(item); model.choose(paste: true) }
.onTapGesture { model.select(item) }
```
Stacking a double-tap recognizer makes SwiftUI hold every single click until the double-click interval
has passed (up to about 500 ms), so selecting a row with the mouse feels dead. From apple-design: "only pay that cost
where double-tap truly exists". Here the first click can select right away.

## Target

A single press-feedback button per row: the first click selects immediately. If the click event has
`clickCount >= 2`, it pastes. Rows scale to 0.98 while pressed (100 ms strong ease-out) and snap back on release.

## Verification

Build. A single click highlights at once. A double click pastes. Pressing and holding shows the pressed scale.
