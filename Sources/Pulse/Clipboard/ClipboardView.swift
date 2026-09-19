import SwiftUI

struct ClipboardView: View {
    @ObservedObject var model: ClipboardModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            searchField
                .padding(.top, 8) // breathing room under the "Clipboard" title
            HStack(spacing: 0) {
                ClipboardList(model: model)
                    .frame(width: 260)
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 4)
                ClipboardPreview(item: model.selectedItem, store: model.store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer
        }
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            TextField("Search clipboard", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.escape) { model.cancel(); return .handled }
                .onKeyPress(keys: [.return]) { press in
                    model.choose(paste: !press.modifiers.contains(.command))
                    return .handled
                }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Spacer()
            KeyHint(keys: "↩", label: "Paste")
            KeyHint(keys: "⌘↩", label: "Copy")
            KeyHint(keys: "esc", label: "Close")
        }
        .padding(.horizontal, 4)
    }
}

/// A keycap plus what it does. Keys read as keys, the label stays quiet.
private struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 17)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white.opacity(0.1)))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

private struct ClipboardList: View {
    @ObservedObject var model: ClipboardModel
    @Namespace private var selectionNamespace

    var body: some View {
        if model.visibleItems.isEmpty {
            Text(model.query.isEmpty ? "Copy something to get started" : "No matches")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    // Lazy: only rows on screen are ever built, however long the history is.
                    LazyVStack(spacing: 2) {
                        ForEach(model.visibleItems) { item in
                            Button {
                                // Select on the first click with no wait. A second click in the same
                                // gesture pastes. (A double-tap recognizer would hold every single click.)
                                model.select(item)
                                if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { model.choose(paste: true) }
                            } label: {
                                ClipRow(
                                    item: item,
                                    icon: model.sourceIcon(for: item),
                                    imageURL: model.store.imageURL(for: item),
                                    isSelected: item.id == model.selectedID,
                                    namespace: selectionNamespace
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableRowStyle())
                            .id(item.id)
                            .contextMenu {
                                Button("Paste") { model.select(item); model.choose(paste: true) }
                                Button("Copy") { model.select(item); model.choose(paste: false) }
                                Divider()
                                Button("Delete", role: .destructive) { model.delete(item) }
                            }
                        }
                    }
                    .padding(.trailing, 8)
                }
                .scrollIndicators(.never)
                .onChange(of: model.selectedID) { _, id in
                    // Slides along with the highlight, like the window switcher.
                    guard let id else { return }
                    withAnimation(Motion.listScroll) { proxy.scrollTo(id) }
                }
            }
        }
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let icon: NSImage?
    let imageURL: URL?
    let isSelected: Bool
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 9) {
            leading
                .frame(width: 22, height: 22)
            Text(item.title.isEmpty ? " " : item.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.14))
                    // One shared highlight that slides between rows instead of blinking.
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        if item.kind == .image, let imageURL {
            Thumbnail(url: imageURL, maxPixelSize: 64, contentMode: .fill)
                .frame(width: 22, height: 22) // bound the fill before clipping, or it spills sideways
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else if let icon {
            Image(nsImage: icon).resizable()
        } else {
            Image(systemName: item.kind == .files ? "doc" : "text.alignleft")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct ClipboardPreview: View {
    let item: ClipItem?
    let store: ClipboardStore

    var body: some View {
        Group {
            switch item?.kind {
            case .text?:
                ScrollView {
                    // Cap what we lay out; a 1 MB string would make text layout the slowest thing we do.
                    Text(String((item?.text ?? "").prefix(20_000)))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .scrollIndicators(.never)
            case .image?:
                if let item, let url = store.imageURL(for: item) {
                    Thumbnail(url: url, maxPixelSize: 900, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(12)
                }
            case .files?:
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item?.fileURLs ?? [], id: \.self) { url in
                        Label(url.path, systemImage: "doc")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            case nil:
                Color.clear
            }
        }
        .id(item?.id) // swaps instantly while arrowing through the list
    }
}

struct Thumbnail: View {
    let url: URL
    let maxPixelSize: Int
    let contentMode: ContentMode
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image = image ?? ThumbnailCache.shared.cached(url, maxPixelSize: maxPixelSize) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.white.opacity(0.06)
            }
        }
        .task(id: url) {
            image = await ThumbnailCache.shared.load(url, maxPixelSize: maxPixelSize)
        }
    }
}
