import AppKit
import SwiftUI

@MainActor
final class ClipboardModel: ObservableObject {
    /// Newest first. Always kept current (cheap array edits), even while the island is closed.
    private(set) var items: [ClipItem] = []

    @Published var query = "" {
        didSet { if isPresented { refilter() } }
    }
    @Published private(set) var visibleItems: [ClipItem] = []
    @Published private(set) var selectedID: String?

    var onChoose: ((ClipItem, _ paste: Bool) -> Void)?
    var onCancel: (() -> Void)?

    let store: ClipboardStore
    private var isPresented = false
    private var iconCache: [String: NSImage] = [:]

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

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        store.delete(id: item.id)
        refilter()
    }

    func clearAll() {
        items.removeAll()
        store.deleteAll()
        refilter()
    }

    // MARK: - Presentation

    func prepareForPresentation() {
        isPresented = true
        query = ""
        refilter()
        selectedID = visibleItems.first?.id
    }

    func didDismiss() {
        isPresented = false
        visibleItems = []
        selectedID = nil
    }

    func move(_ delta: Int) {
        guard !visibleItems.isEmpty else { return }
        let current = visibleItems.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), visibleItems.count - 1)
        withAnimation(Motion.selection) { selectedID = visibleItems[next].id } // highlight glides (owner's call)
    }

    func select(_ item: ClipItem) {
        withAnimation(Motion.selection) { selectedID = item.id }
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
        visibleItems = trimmed.isEmpty ? items : items.filter { item in
            item.title.localizedCaseInsensitiveContains(trimmed)
                || (item.text?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
        if !visibleItems.contains(where: { $0.id == selectedID }) {
            selectedID = visibleItems.first?.id
        }
    }
}
