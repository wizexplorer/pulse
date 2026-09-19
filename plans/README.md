# Animation plans

Written by the `improve-animations` audit (standard effort, 2026-09-18). The project wasn't a git repo at the time,
so the plans have no commit stamp. Line numbers refer to the sources as of that date.

**Settled decision (not re-litigated):** the skill's frequency rule says a keyboard-opened surface
(⌥⇥, ⌃⌘V) should have no open animation, as in Raycast. The product brief explicitly asks for
Dynamic-Island motion, so the island open/close stays animated. It's tuned to the skill's speed
budget instead: content readable in about 200 ms, and nothing on the input path waits for motion.

| # | Plan | Severity | Status |
|---|---|---|---|
| 001 | [No animation on keyboard list navigation](001-instant-keyboard-navigation.md) | HIGH | DONE (partly reversed) |
| 002 | [Content enters fast, no delay](002-fast-content-enter.md) | HIGH | DONE |
| 003 | [Shell springs: bounce only with momentum, snappier close](003-shell-springs.md) | HIGH | DONE |
| 004 | [Remove double-click disambiguation delay](004-click-latency.md) | MEDIUM | DONE |
| 005 | [Honor Reduce Motion](005-reduce-motion.md) | MEDIUM | DONE |

Execution order: 003 → 002 → 001 → 004 → 005. Plan 005 builds on the `Motion` tokens from 002 and 003.
All other plans are independent.

Review: `review-animations` first returned **Block** because the switcher list scroll animated on ⇥. That was fixed, along with the open spring (0.3 s, bounce 0.1), asymmetric press timing, Reduce Motion corner pinning and press opacity, and the header overlap. The second review returned **Approve**. Still open: the swipe open isn't seeded with the gesture's velocity.

Missed opportunities (additive, implemented in the same pass):
- Press feedback on row clicks. The apple-design skill says to respond on pointer-down, and rows had no pressed state.
- Scroll-edge fades on the switcher when more windows exist above or below, to show there's more.

**Owner override (2026-09-18):** in the window switcher, the selection highlight slides between rows again (`Motion.selection`, spring 0.26 s / bounce 0.14, `matchedGeometryEffect`), and the list scroll is animated (`Motion.listScroll`, 160 ms strong ease-out). Both are off under Reduce Motion. The product owner preferred the glide to the instant jump. Don't remove either in future audits. The clipboard list uses the same highlight slide and animated scroll.
