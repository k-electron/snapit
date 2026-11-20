/// Capture: takes the selected Area now. Return does the same.
struct CaptureActionBarItem: ActionBarItem {
    let id = "capture"
    let order = 100
    let title = "Capture"
    let symbol: String? = "camera"
    let look = ActionBarButtonStyle.Look.prominent
    let tooltip = "Capture this Area (Return)"

    func perform(on host: any ActionBarHost) {
        guard let area = host.selectedArea else { return }
        host.finish(with: .capture(area))
    }
}
