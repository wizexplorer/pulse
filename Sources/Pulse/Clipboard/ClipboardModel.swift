import AppKit
import SwiftUI

@MainActor
final class ClipboardModel: ObservableObject {
    /// Newest first. Always kept current (cheap array edits), even while the island is closed.
    private(set) var items: [ClipItem] = []

    @Published var query = "" {
        didSet { if isPresented { refilter() } }
    }
    /// Pinned matches first (newest pin first), then the rest of the history (newest first).
    @Published private(set) var visibleItems: [ClipItem] = []
    /// How many of `visibleItems` are pinned (they lead the list).
    @Published private(set) var pinnedCount = 0
    @Published private(set) var selectedID: String? {
        didSet { if selectedID != oldValue { cancelClear() } }
    }
    /// Clearing takes a second ⌃⇧X within a few seconds. A modal alert would take focus away from
    /// the non-activating panel.
    @Published private(set) var isConfirmingClear = false

    var onChoose: ((ClipItem, _ paste: Bool) -> Void)?
    var onCancel: (() -> Void)?

    let store: ClipboardStore
    private var isPresented = false
    private var iconCache: [String: NSImage] = [:]
    private var clearTimeout: DispatchWorkItem?
    /// Where the pointer was when it last counted as a hover (see `hover(_:)`).
    private var lastPointerLocation: NSPoint?
    /// True when the latest selection change came from the pointer. The list only scrolls to follow
    /// keyboard selection: moving the pointer shouldn't scroll the list out from under it.
    private(set) var selectionFromPointer = false

    init(store: ClipboardStore) {
        self.store = store
        store.loadAll { [weak self] items in
            guard let self else { return }
            // Anything recorded while loading is newer than what was on disk.
            let recorded = Set(self.items.map(\.id))
            self.items += items.filter { !recorded.contains($0.id) }
        }
    }

    var selectedItem: ClipItem? {
        guard let selectedID else { return nil }
        return visibleItems.first { $0.id == selectedID }
    }

    // MARK: - Store updates

    func didRecord(_ item: ClipItem, pruned: [String]) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if !pruned.isEmpty {
            let doomed = Set(pruned)
            items.removeAll { doomed.contains($0.id) }
        }
        if isPresented { refilter() }
    }

    // MARK: - Editing

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let date: Date? = items[index].isPinned ? nil : Date()
        items[index].pinnedDate = date
        store.setPinned(id: item.id, at: date)
        // The row slides into (or out of) the pinned section; the selection rides along with it.
        withAnimation(Motion.listEdit) { refilter() }
    }

    func togglePinOnSelection() {
        if let selectedItem { togglePin(selectedItem) }
    }

    /// Deletes an item. If it was selected, the selection moves to the row that takes its place.
    func delete(_ item: ClipItem) {
        let oldIndex = visibleItems.firstIndex { $0.id == item.id }
        let wasSelected = item.id == selectedID
        selectionFromPointer = false
        items.removeAll { $0.id == item.id }
        store.delete(id: item.id)
        withAnimation(Motion.listEdit) {
            refilter()
            if wasSelected, let oldIndex, !visibleItems.isEmpty {
                selectedID = visibleItems[min(oldIndex, visibleItems.count - 1)].id
            }
        }
    }

    func deleteSelection() {
        if let selectedItem { delete(selectedItem) }
    }

    /// Deletes everything except pinned items. Used as-is by the menu bar and context menu.
    func clearUnpinned() {
        cancelClear()
        guard items.contains(where: { !$0.isPinned }) else { return }
        items.removeAll { !$0.isPinned }
        store.deleteUnpinned()
        selectionFromPointer = false
        withAnimation(Motion.listEdit) {
            refilter()
            selectedID = visibleItems.first?.id
        }
    }

    /// ⌃⇧X: the first press asks, a second press within a few seconds clears.
    func requestClear() {
        if isConfirmingClear {
            clearUnpinned()
            return
        }
        guard items.contains(where: { !$0.isPinned }) else { return }
        isConfirmingClear = true
        let timeout = DispatchWorkItem { [weak self] in self?.cancelClear() }
        clearTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
    }

    func cancelClear() {
        clearTimeout?.cancel()
        clearTimeout = nil
        if isConfirmingClear { isConfirmingClear = false }
    }

    var unpinnedCount: Int { items.count { !$0.isPinned } }

    /// Clipboard-panel shortcuts (Raycast's): ⌘⇧P pin, ⌃X delete, ⌃⇧X clear. Returns true if handled.
    func handleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch (event.charactersIgnoringModifiers?.lowercased(), flags) {
        case ("p", [.command, .shift]): togglePinOnSelection()
        case ("x", [.control]): deleteSelection()
        case ("x", [.control, .shift]): requestClear()
        default: return false
        }
        return true
    }

    // MARK: - Presentation

    func prepareForPresentation() {
        isPresented = true
        lastPointerLocation = NSEvent.mouseLocation
        query = ""
        refilter()
        selectedID = visibleItems.first?.id
    }

    func didDismiss() {
        cancelClear()
        isPresented = false
        visibleItems = []
        selectedID = nil
    }

    func move(_ delta: Int) {
        guard !visibleItems.isEmpty else { return }
        let current = visibleItems.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), visibleItems.count - 1)
        selectionFromPointer = false
        withAnimation(Motion.selection) { selectedID = visibleItems[next].id } // highlight glides (owner's call)
    }

    func select(_ item: ClipItem) {
        selectionFromPointer = true
        withAnimation(Motion.selection) { selectedID = item.id }
    }

    /// Selection follows the pointer, like the window switcher, but only when the pointer itself
    /// moved: a list opening (or scrolling) under a resting cursor doesn't steal the selection.
    func hover(_ item: ClipItem) {
        let location = NSEvent.mouseLocation
        guard location != lastPointerLocation else { return }
        lastPointerLocation = location
        guard item.id != selectedID else { return }
        select(item)
    }

    func choose(paste: Bool) {
        guard let item = selectedItem else { return }
        onChoose?(item, paste)
    }

    func cancel() {
        onCancel?()
    }

    func copyToPasteboard(_ item: ClipItem) {
        Paster.write(item, imageURL: store.imageURL(for: item))
    }

    func sourceIcon(for item: ClipItem) -> NSImage? {
        guard let bundleID = item.sourceBundleID else { return nil }
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        iconCache[bundleID] = icon
        return icon
    }

    private func refilter() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matches = trimmed.isEmpty ? items : items.filter { item in
            item.title.localizedCaseInsensitiveContains(trimmed)
                || (item.text?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
        let pinned = matches.filter(\.isPinned).sorted { $0.pinnedDate! > $1.pinnedDate! }
        visibleItems = pinned + matches.filter { !$0.isPinned }
        pinnedCount = pinned.count
        if !visibleItems.contains(where: { $0.id == selectedID }) {
            selectedID = visibleItems.first?.id
        }
    }
}
