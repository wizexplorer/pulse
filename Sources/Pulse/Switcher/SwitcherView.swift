import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @Namespace private var selectionNamespace
    @StateObject private var scroller = ListScroller()

    var body: some View {
        if model.isLoaded && model.windows.isEmpty {
            if model.needsAccessibility {
                Button(action: Permissions.openAccessibilitySettings) {
                    Label("Allow Pulse in Accessibility settings to see windows", systemImage: "lock.shield")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: IslandMetrics.switcherRowHeight)
            } else {
                Text("No open windows")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: IslandMetrics.switcherRowHeight)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: IslandMetrics.switcherRowSpacing) {
                        ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                            Button { model.choose(index) } label: {
                                SwitcherRow(window: window, isSelected: index == model.selection, namespace: selectionNamespace)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableRowStyle())
                            .id(window.id)
                            .onContinuousHover { phase in
                                if case .active = phase { model.hover(index) }
                            }
                        }
                    }
                    .background(ListScrollerAnchor(scroller: scroller))
                }
                .scrollIndicators(.never)
                .scrollDisabled(model.windows.count <= IslandMetrics.maxVisibleSwitcherRows)
                // Where more windows are out of view, the edge dissolves into the black: shows there's
                // more without a scrollbar, and a row cut off mid-scroll melts away instead of being
                // sliced. Follows the real scroll position, so trackpad scrolling gets it too.
                .mask(EdgeFadeMask(top: scroller.hasContentAbove, bottom: scroller.hasContentBelow, length: 40, intensity: 1.8))
                .onChange(of: model.firstVisibleIndex) { _, first in
                    // Glides on purpose (owner's call); instant under Reduce Motion.
                    guard model.windows.indices.contains(first) else { return }
                    let top = CGFloat(first) * (IslandMetrics.switcherRowHeight + IslandMetrics.switcherRowSpacing)
                    if !scroller.scroll(toTop: top, animated: true) {
                        proxy.scrollTo(model.windows[first].id, anchor: .top)
                    }
                }
                .onChange(of: model.windows.first?.id) { _, _ in
                    // New snapshot: start at the top without animating.
                    if !scroller.scroll(toTop: 0, animated: false), let first = model.windows.first {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
    }
}

private struct SwitcherRow: View {
    let window: WindowInfo
    let isSelected: Bool
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: window.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(window.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(window.appName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if window.isMinimized {
                badge("minus.circle")
            } else if window.isAppHidden {
                badge("eye.slash")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: IslandMetrics.switcherRowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.14))
                    // One shared highlight that slides between rows instead of blinking.
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
    }

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
    }
}

/// Fades the top and/or bottom of a scroll view where content continues out of view: rows dissolve
/// into the island's black instead of being sliced off by a hard edge.
struct EdgeFadeMask: View {
    let top: Bool
    let bottom: Bool
    var length: CGFloat = 14
    /// Steepness: 1 is a plain smoothstep; higher keeps more of the fade near black, so the edge
    /// row dissolves more.
    var intensity: Double = 1

    var body: some View {
        VStack(spacing: 0) {
            fade(opaqueAtTop: false)
                .opacity(top ? 1 : 0)
                .background(Color.black.opacity(top ? 0 : 1))
                .frame(height: length)
            Color.black
            fade(opaqueAtTop: true)
                .opacity(bottom ? 1 : 0)
                .background(Color.black.opacity(bottom ? 0 : 1))
                .frame(height: length)
        }
    }

    /// Eased ramp from clear to opaque. A linear ramp shows a visible band where it starts; easing
    /// both ends makes the content melt away with no edge to spot.
    private var stops: [Gradient.Stop] {
        (0...12).map { i in
            let t = Double(i) / 12
            return Gradient.Stop(color: .black.opacity(pow(t * t * (3 - 2 * t), intensity)), location: t)
        }
    }

    private func fade(opaqueAtTop: Bool) -> LinearGradient {
        LinearGradient(stops: stops, startPoint: opaqueAtTop ? .bottom : .top, endPoint: opaqueAtTop ? .top : .bottom)
    }
}
