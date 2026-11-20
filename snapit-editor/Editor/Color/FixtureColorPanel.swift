import AppKit

/// Test mode's color panel: no window, no preferences. The scripted run chooses a color in it
/// (`editor-color-panel`) the way a user's drag or entry would, and says whether the mouse button
/// is down while it does.
@MainActor
final class FixtureColorPanel: ColorPanelEdge {
    static let shared = FixtureColorPanel()

    private(set) var color = NSColor.white
    private(set) var isShown = false
    /// What `isDragging` reports: set by the run to stand for the mouse button.
    var isDragging = false
    private weak var target: AnyObject?
    private var action: Selector?

    func present(color: NSColor, target: AnyObject, action: Selector) {
        self.color = color
        self.target = target
        self.action = action
        isShown = true
    }

    func dismiss() {
        target = nil
        action = nil
        isShown = false
    }

    /// The user chose `color` in the panel.
    func choose(_ color: NSColor) {
        self.color = color
        guard let target, let action else { return }
        _ = target.perform(action, with: self)
    }
}
