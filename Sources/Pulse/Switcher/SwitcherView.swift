import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @Namespace private var selectionNamespace

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
                }
                .scrollIndicators(.never)
                .scrollDisabled(model.windows.count <= IslandMetrics.maxVisibleSwitcherRows)
                // Soft edges where more windows are out of view: shows there's more without a scrollbar.
                .mask(EdgeFadeMask(
                    top: model.firstVisibleIndex > 0,
                    bottom: model.firstVisibleIndex + IslandMetrics.maxVisibleSwitcherRows < model.windows.count
                ))
                .onChange(of: model.firstVisibleIndex) { _, first in
                    // Smooth on purpose (see Motion.listScroll); instant under Reduce Motion.
                    guard model.windows.indices.contains(first) else { return }
                    withAnimation(Motion.listScroll) { proxy.scrollTo(model.windows[first].id, anchor: .top) }
                }
                .onChange(of: model.windows.first?.id) { _, _ in
                    // New snapshot: start at the top without animating.
                    if let first = model.windows.first { proxy.scrollTo(first.id, anchor: .top) }
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

/// Fades the top and/or bottom 14 pt of a scroll view: a soft edge instead of a hard clip.
struct EdgeFadeMask: View {
    let top: Bool
    let bottom: Bool
    private let fade: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [top ? .clear : .black, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
            Color.black
            LinearGradient(colors: [.black, bottom ? .clear : .black], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
        }
    }
}
