# Pulse

Turns the MacBook notch into a Dynamic Island with a **window switcher** (⌥⇥ and three-finger
swipe) and a **clipboard history** with images (⌃⌘V). Written for AppKit + SwiftUI, with no dependencies.
The app is 444 KB and uses about 0% CPU when idle.

## Build & run

Only the Command Line Tools are needed. You don't need Xcode.

```sh
make install    # build, copy to /Applications, launch (use this for everyday use)
make run        # build and launch from build/ (for development)
```

The installed copy turns on **Open at Login** the first time it runs. You can toggle it from the
menu bar icon or in System Settings ▸ General ▸ Login Items. After changing code, run
`make install` again to update the installed app. The login item keeps pointing at it.

On first launch, grant **Accessibility** in System Settings ▸ Privacy & Security.

**Keep the permission across rebuilds:** macOS ties the permission to the code signature. An ad-hoc
signature changes on every build, which silently revokes the permission. Run
`./scripts/create-signing-identity.sh` once, and every later `make app` signs with a stable
"Pulse Developer" identity.

**Switcher shows no windows or swipes do nothing?** Pulse doesn't have Accessibility access. The
menu bar icon's first item shows the status. System Settings can show Pulse as switched on even
after a signature change has made that grant stale. To clear it, run
`tccutil reset Accessibility dev.pulse.Pulse`, relaunch Pulse, and allow it again. To watch the logs, run
`log stream --predicate 'subsystem == "dev.pulse.Pulse"' --level info`.

**Trackpad:** set System Settings ▸ Trackpad ▸ More Gestures ▸ *Swipe between full-screen
applications* to **four fingers**. With the default setting, macOS also acts on your three-finger swipe.

## Controls

| | |
|---|---|
| ⌥⇥ / ⌥⇧⇥ | Open the switcher on the previous window. Keep ⌥ held and press ⇥ (or ↑↓) to move. Release ⌥ to switch. Esc cancels. |
| 3-finger swipe ←/→ | Open the switcher. Keep swiping to step through windows. Lift your fingers to switch. |
| ⌃⌘V | Clipboard history. Type to search, use ↑↓ to move, ↩ to paste into the previous app, and ⌘↩ to only copy. |
| ⌘⇧P / ⌃X / ⌃⇧X | In the clipboard: pin or unpin the selected item (pinned items stay at the top and are never pruned), delete it, or clear everything that isn't pinned (press twice to confirm). |
| Lock screen | While the Mac is locked, the island widens beside the notch with a lock. A wrong password or finger shakes it; unlocking swings the lock open and folds the island back into the notch. |

## How it works (research summary)

| Feature | Approach | Prior art |
|---|---|---|
| Island window | A borderless, non-activating `NSPanel` at the `.mainMenu + 3` level that appears on all Spaces and over full-screen apps. The notch size comes from `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`. Macs without a notch get a simulated one. | boring.notch, NotchNook, DynamicNotchKit |
| Animation | An animatable `NotchShape` whose closed state exactly matches the hardware notch, so the island grows out of it. The shell uses springs (`Motion.swift`). Content blurs and scales in after the shell starts moving. Selection uses `matchedGeometryEffect`. | iOS Dynamic Island |
| Window list | Built when the switcher opens: WindowServer z-order (`CGWindowListCopyWindowInfo`, the most-recently-used order, needs no permission) joined with per-app Accessibility data fetched concurrently (one batched IPC per window). The private `_AXUIElementGetWindow` links the two. | AltTab |
| Focusing a window | Private SkyLight `_SLPSSetFrontProcessWithOptions` plus a synthetic "make key" event record, then `AXRaise`. If the private symbols disappear, it falls back to public APIs. All private symbols are resolved at runtime with `dlsym`. | AltTab, yabai, Hammerspoon |
| ⌥⇥ | A Carbon `RegisterEventHotKey`, so the WindowServer does the matching and Pulse doesn't process keystrokes. macOS 15.0 briefly refused Option-only hotkeys. If registration fails, a narrow keyboard event tap is created instead. Release of ⌥ is detected by a monitor that exists only while the switcher is open. | |
| 3-finger swipe | A listen-only HID tap for gesture events on its own thread, reading `NSTouch` positions. It never delays the cursor. A second, active tap swallows the swipe once it's recognised, and it's enabled only while 3 fingers are down. | AltTab |
| Clipboard | Polls `changeCount` (one cheap IPC) every 0.75 s with 0.4 s leeway. It also checks on every app switch and pauses completely during sleep, screen sleep and fast user switching. Honours nspasteboard.org's concealed/transient markers, so password managers are skipped. Stores entries in SQLite (WAL) and images as PNG files. Duplicates are found by SHA-256. | Raycast, Maccy |
| Lock screen | A private SkyLight space at absolute level 400 puts the island's window above the lock screen. Lock and unlock come from loginwindow's distributed notifications. Failed and successful attempts come from loginwindow's own log (`log stream` with a two-message predicate), which runs only while the screen is locked. Motion is fitted frame by frame to a recording of Alcove. | SkyLightWindow, Alcove |

## Efficiency rules this codebase follows

- **When idle, the island doesn't exist on screen.** The panel is ordered out, so nothing renders or composites.
- **No background tracking.** Window data is gathered only when the switcher opens, and within the opening animation.
- **Session-scoped input.** Arrow, Esc and Return hotkeys and the ⌥-release monitor are registered only while the switcher is open.
- **Event driven.** App activation, sleep/wake and permission changes arrive as notifications. The clipboard's `changeCount` check is the only timer, and it stops when the Mac or display sleeps.
- **Off the main thread and on efficiency cores.** Hashing, PNG encoding and SQLite run at utility QoS. Accessibility work runs on its own queues with 150 ms timeouts, so a hung app can't stall Pulse.
- **Never decode full images.** ImageIO downsamples straight to the display size, and the results go into a bounded `NSCache`.
- **No per-second UI timers.** Relative dates are static strings (`Text(.relative)` would start a timer per row), and lists are lazy.

## Layout

```
Sources/Pulse/
  App/        main, AppDelegate (wiring + menu bar item), Config (all tunables)
  Island/     IslandPanel, IslandController (present/dismiss + input sessions), IslandRootView,
              NotchShape, NotchGeometry/IslandMetrics, Motion (all animation curves)
  Input/      HotKeyCenter (Carbon), KeyboardTap (fallback), TrackpadGestureMonitor
  Switcher/   WindowEnumerator, WindowFocuser, SwitcherModel, SwitcherView
  Clipboard/  ClipboardMonitor, ClipboardStore (+SQLiteDatabase), ClipboardModel, ClipboardView,
              ThumbnailCache, Paster
  System/     Permissions, PrivateAPI (dlsym'd SkyLight/HIServices), AppActivationTracker
Sources/PulseObjC/  NSException catcher (NSTouch can raise)
```

## Known limits / next steps

- Windows on other Spaces are listed only if their app reports them through Accessibility. Full
  cross-Space listing needs more SkyLight calls.
- There are no window thumbnails. They would need Screen Recording permission and ScreenCaptureKit, so if added, capture only while the switcher is open.
- Rich text is pasted as plain text. RTF/HTML are not stored yet.
- There's no settings UI yet. Everything tunable lives in `Config.swift`, and launch-at-login can be added with `SMAppService.mainApp`.
- Private APIs are not allowed on the Mac App Store. Distribute it directly (Developer ID and notarization).
