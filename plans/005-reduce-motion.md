# 005 — Honor Reduce Motion

- **Status**: DONE · **Commit**: n/a · **Severity**: MEDIUM · **Category**: Accessibility

## Problem

Nothing checks `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`. The island grows, springs
and scales content for everyone.

## Target

When System Settings ▸ Accessibility ▸ Display ▸ Reduce motion is on:
- The shell doesn't change size on screen. It appears at its final size and cross-fades in or out (200 ms, strong ease-out).
- Content fades only, with no blur or scale.
- No list-scroll animation.
- Opacity feedback stays: reduced motion means gentler, not none.

Read the flag live (a computed `Motion.reduceMotion`), so toggling the setting applies on the next open.

## Verification

Build. Turn on Reduce motion, then open and close both modes: nothing grows or slides, and everything fades.
Turn it off and the springs come back.
