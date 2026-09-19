# 002 — Content enters fast, no delay

- **Status**: DONE · **Commit**: n/a · **Severity**: HIGH · **Category**: Easing & duration

## Problem

`Sources/Pulse/Island/Motion.swift:14`: `contentIn = .smooth(duration: 0.32).delay(0.07)`, with
`blur(10)` and `scale(0.9)` in `IslandContentEffect`. The list becomes readable about 390 ms after a keyboard
shortcut, which is over the 300 ms UI budget, on something opened tens of times a day. The 0.9 scale also
travels far enough that you can see the content "zoom".

## Target

```swift
static let strongEaseOut = (0.23, 1.0, 0.32, 1.0)            // cubic-bezier(0.23, 1, 0.32, 1)
static var contentIn: Animation  { .timingCurve(0.23, 1, 0.32, 1, duration: 0.2).delay(0.03) }
static let contentOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.1)
// IslandContentEffect: opacity(p), blur((1-p) * 4), scale(0.96 + 0.04 * p, anchor: .top)
```
The 30 ms delay stays on purpose: content appears once the shell has started opening, so it grows out of
the notch instead of popping in ahead of the shell. The blur stays small (4 pt, under the 20 limit) and hides the crossfade.

## Verification

Build. Feel check: ⌥⇥ must feel as quick as ⌘⇥, and the first row should be readable before the shell has
finished opening. The exit must never be slower than the entrance.
