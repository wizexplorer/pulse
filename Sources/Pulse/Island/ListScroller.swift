import AppKit
import SwiftUI

/// Smooth, animated scrolling for SwiftUI lists on macOS.
///
/// On macOS, `ScrollViewReader.scrollTo` inside `withAnimation` does not animate: the list jumps a
/// whole row in a single frame. So we reach the `NSScrollView` backing the SwiftUI `ScrollView` and
/// animate its clip view directly. That's the native way to scroll smoothly, and trackpad/wheel
/// scrolling keeps working.
@MainActor
final class ListScroller {
    fileprivate weak var scrollView: NSScrollView?

    /// Scrolls so that content offset `top` (points from the top of the list) is at the top edge.
    /// Returns false if the scroll view hasn't been found yet (the caller can fall back to `scrollTo`).
    @discardableResult
    func scroll(toTop top: CGFloat, animated: Bool) -> Bool {
        guard let scrollView, let document = scrollView.documentView else { return false }
        let clip = scrollView.contentView
        let visibleHeight = clip.bounds.height
        let clamped = min(max(top, 0), max(document.frame.height - visibleHeight, 0))
        let y = document.isFlipped ? clamped : document.frame.height - visibleHeight - clamped
        let origin = NSPoint(x: clip.bounds.origin.x, y: y)

        if animated && !Motion.reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.listScrollDuration
                context.timingFunction = Motion.listScrollTiming
                context.allowsImplicitAnimation = true
                clip.animator().setBoundsOrigin(origin)
            }
        } else {
            clip.setBoundsOrigin(origin)
        }
        scrollView.reflectScrolledClipView(clip)
        return true
    }

    /// Scrolls the least amount needed to show a row spanning `rowTop...rowBottom` (list coordinates).
    @discardableResult
    func reveal(rowTop: CGFloat, rowBottom: CGFloat, animated: Bool) -> Bool {
        guard let scrollView, let document = scrollView.documentView else { return false }
        let clip = scrollView.contentView
        let visibleHeight = clip.bounds.height
        let currentTop = document.isFlipped
            ? clip.bounds.origin.y
            : document.frame.height - visibleHeight - clip.bounds.origin.y
        if rowTop < currentTop {
            return scroll(toTop: rowTop, animated: animated)
        }
        if rowBottom > currentTop + visibleHeight {
            return scroll(toTop: rowBottom - visibleHeight, animated: animated)
        }
        return true
    }
}

/// Invisible view placed inside a SwiftUI `ScrollView`'s content; hands its enclosing
/// `NSScrollView` to a `ListScroller`.
struct ListScrollerAnchor: NSViewRepresentable {
    let scroller: ListScroller

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.scroller = scroller
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.scroller = scroller
        view.connect()
    }

    final class AnchorView: NSView {
        weak var scroller: ListScroller?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            connect()
        }

        func connect() {
            if let scrollView = enclosingScrollView { scroller?.scrollView = scrollView }
        }
    }
}
