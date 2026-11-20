import AppKit

/// The edge to the macOS color panel. The real panel is `NSColorPanel.shared`, which keeps its
/// mode and swatches in the helper's own preferences; test mode swaps in a fixture so a scripted
/// run never touches them or puts a panel on the user's screen.
@MainActor
protocol ColorPanelEdge: AnyObject {
    /// The color the panel shows now.
    var color: NSColor { get }
    /// True while the user is dragging inside the panel (the mouse button is down).
    var isDragging: Bool { get }
    /// Shows the panel with `color`, sending `action` to `target` on every change the user makes.
    func present(color: NSColor, target: AnyObject, action: Selector)
    func dismiss()
}

@MainActor
enum ColorPanelEdges {
    static let current: any ColorPanelEdge = TestMode.isActive ? FixtureColorPanel.shared : SystemColorPanel()
}

/// `NSColorPanel.shared`: a color wheel that reports continuously as the user drags.
@MainActor
final class SystemColorPanel: ColorPanelEdge {
    var color: NSColor { NSColorPanel.shared.color }
    var isDragging: Bool { NSEvent.pressedMouseButtons & 1 != 0 }

    func present(color: NSColor, target: AnyObject, action: Selector) {
        let panel = NSColorPanel.shared
        panel.isContinuous = true
        panel.showsAlpha = false
        panel.mode = .wheel
        panel.setTarget(target)
        panel.setAction(action)
        panel.color = color
        panel.orderFront(nil)
    }

    func dismiss() {
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderOut(nil)
    }
}
