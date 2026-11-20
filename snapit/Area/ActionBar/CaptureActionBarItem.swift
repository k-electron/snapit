import CoreGraphics

/// Capture: takes the selected Area now. Enter does the same.
struct CaptureActionBarItem: ActionBarItem {
    let id = "capture"
    let order = 100
    let title = "Capture"
    let look = ActionBarButtonControl.Look.prominent
    let tooltip = "Capture this Area (Enter)"

    /// A camera: body, lens and viewfinder.
    var glyph: CGPath? {
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: 1, y: 1, width: 12, height: 9), cornerWidth: 2, cornerHeight: 2)
        path.addEllipse(in: CGRect(x: 4.6, y: 3, width: 4.8, height: 4.8))
        path.move(to: CGPoint(x: 4.5, y: 12.4))
        path.addLine(to: CGPoint(x: 9.5, y: 12.4))
        return path
    }

    func perform(on host: any ActionBarHost) {
        guard let area = host.selectedArea else { return }
        host.finish(with: .capture(area))
    }
}
