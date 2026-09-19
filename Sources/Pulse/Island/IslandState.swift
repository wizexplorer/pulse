import SwiftUI

enum IslandMode: Equatable {
    case idle
    case switcher
    case clipboard
}

/// Shell state the root view renders. Only `IslandController` mutates it, always inside an animation.
@MainActor
final class IslandState: ObservableObject {
    @Published var mode: IslandMode = .idle
    // Width and height are separate so each can move on its own spring (see Motion.close*).
    @Published var width: CGFloat = IslandMetrics.closedSize(.fallback).width
    @Published var height: CGFloat = IslandMetrics.closedSize(.fallback).height
    @Published var notch: NotchGeometry = .fallback
    /// Which content is laid out in the island. Outlives `mode` during a close, so the content can
    /// fade out inside the shrinking shell instead of being removed at once.
    @Published var contentMode: IslandMode = .idle
    /// Drives the content's fade/blur (animated); see IslandContentEffect.
    @Published var contentShown = false

    var isOpen: Bool { mode != .idle }

    /// Setting both at once moves them together, on whatever animation is current.
    var size: CGSize {
        get { CGSize(width: width, height: height) }
        set {
            width = newValue.width
            height = newValue.height
        }
    }
}
