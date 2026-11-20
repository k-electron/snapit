import CoreGraphics

/// Cancel: ends the Capture without taking one. Esc does the same.
struct CancelActionBarItem: ActionBarItem {
    let id = "cancel"
    let order = 900
    let title = "Cancel"
    let tooltip = "Cancel (Esc)"

    /// A cross.
    var glyph: CGPath? {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 3, y: 3))
        path.addLine(to: CGPoint(x: 11, y: 11))
        path.move(to: CGPoint(x: 3, y: 11))
        path.addLine(to: CGPoint(x: 11, y: 3))
        return path
    }

    func perform(on host: any ActionBarHost) {
        host.finish(with: .cancel)
    }
}
