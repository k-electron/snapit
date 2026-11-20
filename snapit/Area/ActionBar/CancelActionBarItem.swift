/// Cancel: ends the Capture without taking one. Esc does the same.
struct CancelActionBarItem: ActionBarItem {
    let id = "cancel"
    let order = 900
    let title = "Cancel"
    let symbol: String? = "xmark"
    let tooltip = "Cancel (Esc)"

    func perform(on host: any ActionBarHost) {
        host.finish(with: .cancel)
    }
}
