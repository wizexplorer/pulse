import AppKit
import SwiftUI

@MainActor
final class SwitcherModel: ObservableObject {
    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var selection = 0
    @Published private(set) var isLoaded = false
    /// Without Accessibility access every app reports zero windows, so say that instead of "no windows".
    @Published private(set) var needsAccessibility = false
    /// Index of the top row in view. Scrolls only when the selection enters the top or bottom third.
    @Published private(set) var firstVisibleIndex = 0

    /// Last known window count, used to size the island before a fresh snapshot arrives so it
    /// doesn't open at one row and then jump.
    private var lastWindowCount = 1
    var rowCountForLayout: Int { isLoaded ? windows.count : lastWindowCount }

    var onLoaded: (() -> Void)?
    var onCommit: ((WindowInfo) -> Void)?
    var onCancel: (() -> Void)?

    // Input can arrive before the (async) window list does; it is replayed once it lands.
    private var pendingSteps = 0
    private var pendingCommit = false
    private var generation = 0
    private var hoverAnchor: NSPoint?

    func begin(initialStep: Int) {
        generation += 1
        let current = generation
        isLoaded = false
        pendingSteps = initialStep
        pendingCommit = false
        hoverAnchor = NSEvent.mouseLocation
        needsAccessibility = !Permissions.hasAccessibility

        WindowEnumerator.snapshot { [weak self] list in
            guard let self, current == self.generation else { return }
            Log.switcher.info("snapshot: \(list.count) windows, accessibility: \(!self.needsAccessibility)")
            self.windows = list
            self.lastWindowCount = max(list.count, 1)
            self.isLoaded = true
            self.selection = self.wrapped(self.pendingSteps)
            self.pendingSteps = 0
            self.firstVisibleIndex = 0
            self.updateViewport()
            self.onLoaded?()
            if self.pendingCommit { self.commit() }
        }
    }

    func step(_ delta: Int) {
        guard isLoaded else {
            pendingSteps += delta
            return
        }
        guard !windows.isEmpty else { return }
        // The highlight glides to its new row (owner's call, see Motion.selection).
        withAnimation(Motion.selection) { selection = wrapped(selection + delta) }
        updateViewport()
    }

    /// ⌥⇥ tapped and released at once: focus the target window with no UI at all.
    func quickSwitch(step: Int) {
        generation += 1
        let current = generation
        WindowEnumerator.snapshot { [weak self] list in
            guard let self, current == self.generation, !list.isEmpty else { return }
            let count = list.count
            let index = ((step % count) + count) % count
            self.lastWindowCount = count
            self.onCommit?(list[index])
        }
    }

    private func updateViewport() {
        let visible = IslandMetrics.maxVisibleSwitcherRows
        guard windows.count > visible else {
            firstVisibleIndex = 0
            return
        }
        let margin = IslandMetrics.switcherScrollMargin
        var first = firstVisibleIndex
        first = max(first, selection - (visible - 1 - margin)) // entering the bottom third
        first = min(first, selection - margin)                 // entering the top third
        firstVisibleIndex = min(max(first, 0), windows.count - visible)
    }

    /// Selection follows the pointer only once it actually moves, so a list appearing under a
    /// resting cursor doesn't steal the keyboard's selection.
    func hover(_ index: Int) {
        if let anchor = hoverAnchor {
            guard NSEvent.mouseLocation != anchor else { return }
            hoverAnchor = nil
        }
        guard windows.indices.contains(index), index != selection else { return }
        withAnimation(Motion.selection) { selection = index }
        // No viewport update: moving the pointer shouldn't scroll the list out from under it.
    }

    func choose(_ index: Int) {
        guard windows.indices.contains(index) else { return }
        selection = index
        commit()
    }

    func commit() {
        guard isLoaded else {
            pendingCommit = true
            return
        }
        guard windows.indices.contains(selection) else {
            onCancel?()
            return
        }
        let window = windows[selection]
        generation += 1 // ignore anything still in flight
        onCommit?(window)
    }

    func cancel() {
        generation += 1
        onCancel?()
    }

    /// Drop AX references once the island has fully closed.
    func reset() {
        windows = []
        selection = 0
        firstVisibleIndex = 0
        isLoaded = false
    }

    private func wrapped(_ index: Int) -> Int {
        guard !windows.isEmpty else { return 0 }
        let count = windows.count
        return ((index % count) + count) % count
    }
}
