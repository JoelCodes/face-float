import AppKit

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = NSSize(width: 120, height: 120)
    }

    func apply(shape: WindowShape) {
        switch shape {
        case .circle:
            // Snap to a square, then lock the aspect ratio.
            let side = min(frame.width, frame.height)
            var f = frame
            f.size = NSSize(width: side, height: side)
            setFrame(f, display: true)
            contentAspectRatio = NSSize(width: 1, height: 1)
        case .rectangle:
            // Setting resizeIncrements clears the aspect-ratio constraint.
            resizeIncrements = NSSize(width: 1, height: 1)
        }
    }
}
