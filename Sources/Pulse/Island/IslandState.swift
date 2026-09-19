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
    @Published var size: CGSize = IslandMetrics.closedSize(.fallback)
    @Published var notch: NotchGeometry = .fallback

    var isOpen: Bool { mode != .idle }
}
