import CoreGraphics

/// Pick Color: opens the Color picker over the Area. P does the same.
struct PickColorActionBarItem: ActionBarItem {
    let id = "pick-color"
    let order = 800
    let title = "Pick Color"
    let tooltip = "Pick a color from the screen (P)"
    let keyEquivalent: String? = "p"

    /// A bulb on a slanted barrel with a tip.
    var glyph: CGPath? {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: 8, y: 8, width: 4.6, height: 4.6))
        path.move(to: CGPoint(x: 8.6, y: 8.6))
        path.addLine(to: CGPoint(x: 3.6, y: 3.6))
        path.move(to: CGPoint(x: 3.6, y: 3.6))
        path.addLine(to: CGPoint(x: 1.6, y: 1.6))
        path.move(to: CGPoint(x: 6, y: 6.4))
        path.addLine(to: CGPoint(x: 7.4, y: 5))
        return path
    }

    func perform(on host: any ActionBarHost) {
        host.beginPickingColor()
    }
}
