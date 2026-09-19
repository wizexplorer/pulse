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
        // Corners scale with the island's live height (stepped every frame by ShellAnimator), so the
        // island stays round while it grows and shrinks and only tightens into the notch's radius
        // near the end. Tied to the open/closed flag instead, they snapped tight at the start of a
        // close and the big shell read as a black box. Under Reduce Motion they stay open (it only fades).
        let grown = Motion.reduceMotion ? 1 : min(max(
            (state.height - state.notch.size.height) / IslandMetrics.cornerGrowthDistance, 0), 1)
        let topRadius = IslandMetrics.closedTopRadius + (IslandMetrics.openTopRadius - IslandMetrics.closedTopRadius) * grown
        let bottomRadius = IslandMetrics.closedBottomRadius + (IslandMetrics.openBottomRadius - IslandMetrics.closedBottomRadius) * grown
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
        // Content is laid out against the open inset, so it never reflows as the corners change.
        let inset = IslandMetrics.openTopRadius

        ZStack(alignment: .top) {
            if open {
                // Clicks on the transparent canvas around the island dismiss it.
                Color.black.opacity(0.001)
                    .onTapGesture(perform: onBackgroundTap)
            }

            ZStack(alignment: .top) {
                shape.fill(Color.black)
                // Content stays in the hierarchy for the whole open/close and fades through an animated
                // value, NOT a SwiftUI transition: on macOS, views mid-transition are drawn outside the
                // parent's clip, so content leaked out of the growing island.
                Group {
                    header
                        .frame(height: state.notch.size.height)
                        .padding(.horizontal, inset + IslandMetrics.contentInset + 4)
                    content
                        .padding(.top, state.notch.size.height)
                        .padding(.horizontal, inset + IslandMetrics.contentInset)
                        .padding(.bottom, IslandMetrics.contentInset)
                }
                .modifier(IslandContentEffect(progress: state.contentShown ? 1 : 0, reduceMotion: Motion.reduceMotion))
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
        ZStack {
            switch state.contentMode {
            case .idle: EmptyView()
            case .switcher: SwitcherHeader(model: switcher, notchWidth: state.notch.size.width)
            case .clipboard: ClipboardHeader(model: clipboard, notchWidth: state.notch.size.width)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.contentMode {
        case .idle:
            EmptyView()
        case .switcher:
            SwitcherView(model: switcher)
                .frame(
                    width: IslandMetrics.switcherWidth - 2 * (IslandMetrics.openTopRadius + IslandMetrics.contentInset),
                    height: IslandMetrics.switcherListHeight(rows: switcher.rowCountForLayout)
                )
        case .clipboard:
            ClipboardView(model: clipboard)
                .frame(
                    width: IslandMetrics.clipboardSize.width - 2 * (IslandMetrics.openTopRadius + IslandMetrics.contentInset),
                    height: IslandMetrics.clipboardSize.height - IslandMetrics.contentInset
                )
        }
    }
}
