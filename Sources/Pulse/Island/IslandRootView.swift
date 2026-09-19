import SwiftUI

/// Title on the left of the notch, status on the right.
struct IslandHeaderLayout: View {
    let symbol: String
    let title: String
    let detail: String
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: notchWidth + 24)
            Text(detail)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .contentTransition(.identity)
        }
    }
}

private struct SwitcherHeader: View {
    @ObservedObject var model: SwitcherModel
    let notchWidth: CGFloat

    var body: some View {
        IslandHeaderLayout(
            symbol: "macwindow.on.rectangle",
            title: "Windows",
            detail: model.windows.isEmpty ? "" : "\(model.selection + 1) of \(model.windows.count)",
            notchWidth: notchWidth
        )
    }
}

private struct ClipboardHeader: View {
    @ObservedObject var model: ClipboardModel
    let notchWidth: CGFloat

    var body: some View {
        IslandHeaderLayout(
            symbol: "doc.on.clipboard",
            title: "Clipboard",
            detail: model.visibleItems.count == 1 ? "1 item" : "\(model.visibleItems.count) items",
            notchWidth: notchWidth
        )
    }
}

struct IslandRootView: View {
    @ObservedObject var state: IslandState
    // Held as plain references on purpose: the root must not re-render when feature models change.
    let switcher: SwitcherModel
    let clipboard: ClipboardModel
    let onBackgroundTap: () -> Void

    var body: some View {
        let open = state.isOpen
        // Under Reduce Motion the shell only fades, so its corners must not morph either.
        let openShape = open || Motion.reduceMotion
        let topRadius = openShape ? IslandMetrics.openTopRadius : IslandMetrics.closedTopRadius
        let bottomRadius = openShape ? IslandMetrics.openBottomRadius : IslandMetrics.closedBottomRadius
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)

        ZStack(alignment: .top) {
            if open {
                // Clicks on the transparent canvas around the island dismiss it.
                Color.black.opacity(0.001)
                    .onTapGesture(perform: onBackgroundTap)
            }

            ZStack(alignment: .top) {
                shape.fill(Color.black)
                if open {
                    header
                        .frame(height: state.notch.size.height)
                        .padding(.horizontal, topRadius + IslandMetrics.contentInset + 4)
                        .transition(.islandContent)
                }
                content
                    .padding(.top, state.notch.size.height)
                    .padding(.horizontal, topRadius + IslandMetrics.contentInset)
                    .padding(.bottom, IslandMetrics.contentInset)
            }
            .frame(width: state.size.width, height: state.size.height, alignment: .top)
            .clipShape(shape)
            .shadow(color: .black.opacity(open ? 0.35 : 0), radius: 14, y: 6)
            // Reduce Motion: a closed island is invisible, so opening is a cross-fade, not a growth.
            .opacity(open || !Motion.reduceMotion ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Windows overlapping the notch get a top safe-area inset; SwiftUI would otherwise push the
        // whole island down by the notch height, right under the menu bar.
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    /// Uses the dead strip beside the camera housing, the way the iPhone's Island does: what this is on the
    /// left, where you are on the right. The gap in the middle clears the hardware notch.
    @ViewBuilder
    private var header: some View {
        // ZStack, so an outgoing and incoming header overlap while swapping modes instead of sitting side by side.
        ZStack {
            switch state.mode {
            case .idle: EmptyView()
            case .switcher: SwitcherHeader(model: switcher, notchWidth: state.notch.size.width).transition(.islandContent)
            case .clipboard: ClipboardHeader(model: clipboard, notchWidth: state.notch.size.width).transition(.islandContent)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.mode {
        case .idle:
            EmptyView()
        case .switcher:
            SwitcherView(model: switcher)
                .frame(
                    width: IslandMetrics.switcherWidth - 2 * (IslandMetrics.openTopRadius + IslandMetrics.contentInset),
                    height: IslandMetrics.switcherListHeight(rows: switcher.rowCountForLayout)
                )
                .transition(.islandContent)
        case .clipboard:
            ClipboardView(model: clipboard)
                .frame(
                    width: IslandMetrics.clipboardSize.width - 2 * (IslandMetrics.openTopRadius + IslandMetrics.contentInset),
                    height: IslandMetrics.clipboardSize.height - IslandMetrics.contentInset
                )
                .transition(.islandContent)
        }
    }
}
