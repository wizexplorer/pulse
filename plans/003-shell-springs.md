# 003 — Shell springs: bounce only with momentum, snappier close

- **Status**: DONE · **Commit**: n/a · **Severity**: HIGH · **Category**: Physicality / Easing & duration

## Problem

`Sources/Pulse/Island/Motion.swift:9-12`:
```swift
static let open = Animation.spring(duration: 0.5, bounce: 0.26)
static let resize = Animation.spring(duration: 0.42, bounce: 0.18)
static let close = Animation.spring(duration: 0.4, bounce: 0.0)
static let closeSettleTime: TimeInterval = 0.45
```
- The same bouncy open is used for a keypress and for a three-finger swipe. The apple-design skill: add bounce
  only when the gesture carried momentum. A keypress has none, and a swipe does.
- 0.5 s is long for a keyboard surface. Close is the system's response after a commit, so it should
  snap. Asymmetric timing: the dismissal is faster than the entrance.

## Target

```swift
static let open          = Animation.spring(duration: 0.36, bounce: 0.14) // keyboard, pointer: a hint of Island overshoot
static let openFromSwipe = Animation.spring(duration: 0.40, bounce: 0.24) // the swipe carried momentum
static let resize        = Animation.spring(duration: 0.34, bounce: 0.08) // on-screen morph between modes
static let close         = Animation.spring(duration: 0.30, bounce: 0)    // snap shut, no bounce
static let closeSettleTime: TimeInterval = 0.34
```
`IslandController.present(_:animation:)` takes the curve, and `beginSwitcher` passes `openFromSwipe` for
`.gesture`.

## Verification

Build. Feel check (screen recording played at 0.25×): the keyboard open overshoots by a hair, the swipe open
visibly more, and the close lands without any overshoot or wobble.
