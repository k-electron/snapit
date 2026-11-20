import AppKit
import Foundation

nonisolated extension SocketCommand {
    /// What the Action bar shows now: `frame=<x>,<y> <w>x<h>` (display points from the display's
    /// top-left corner, `none` when no bar shows), then one `item <id>|<title>|<tooltip>|<key>|<frame>`
    /// line per item in the order the bar lays them out, `<key>` being `none` when the item has no
    /// key. The frame is the item's whole tile, which is its hit area. The bar is clicked with
    /// `overlay-mouse`, like the rest of the overlay; `overlay-facts` has the `tooltip`.
    static let overlayActionBar = SocketCommand("overlay-actionbar")
}

extension SocketCommandRegistry {
    /// The Action bar's test-mode commands. They exist only while test mode is on; the Area
    /// overlay's registration calls this.
    func registerActionBarTestCommands() {
        guard TestMode.isActive else { return }

        register(.overlayActionBar) { _ in
            guard let controller = AreaCaptureFlow.activeOverlay else { return "none" }
            return controller.actionBarFacts().joined(separator: "\n")
        }
    }
}

extension AreaOverlayController {
    /// The Action bar's frame on the display that has it.
    var actionBarFrame: CGRect? { containers.lazy.compactMap(\.actionBarFrame).first }

    func actionBarFacts() -> [String] {
        func describe(_ rect: CGRect) -> String {
            func number(_ value: Double) -> String {
                var text = String(format: "%.2f", value)
                while text.contains("."), text.hasSuffix("0") || text.hasSuffix(".") { text.removeLast() }
                return text
            }
            return "\(number(rect.minX)),\(number(rect.minY)) \(number(rect.width))x\(number(rect.height))"
        }
        guard let container = containers.first(where: { $0.actionBarFrame != nil }), let bar = container.actionBarFrame,
            let layers = container.actionBar
        else { return ["frame=none"] }
        var lines = ["frame=\(describe(bar))"]
        for item in ActionBarRegistry.all {
            let tile = layers.control(id: item.id)?.frame.offsetBy(dx: bar.minX, dy: bar.minY)
            lines.append(
                "item \(item.id)|\(item.title)|\(item.tooltip)|\(item.keyEquivalent ?? "none")|\(tile.map(describe) ?? "none")")
        }
        return lines
    }
}
