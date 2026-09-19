import AppKit
import Carbon.HIToolbox

enum Paster {
    static func write(_ item: ClipItem, imageURL: URL?) {
        let pasteboard = NSPasteboard.general
        switch item.kind {
        case .text:
            pasteboard.clearContents()
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            guard let imageURL, let data = try? Data(contentsOf: imageURL) else { return }
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
        case .files:
            pasteboard.clearContents()
            pasteboard.writeObjects(item.fileURLs as [NSURL])
        }
    }

    /// Synthesizes ⌘V into the frontmost app. Requires Accessibility permission.
    static func sendPasteShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
