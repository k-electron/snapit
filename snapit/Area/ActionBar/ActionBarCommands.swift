import AppKit
import Foundation

nonisolated extension SocketCommand {
    /// What the Action bar shows now: `frame=<x>,<y> <w>x<h>` (display points from the display's
    /// top-left corner, `none` when no bar shows), then one `item <id>|<title>|<tooltip>|<key>|<frame>`
    /// line per item in the order the bar lays them out, `<key>` and `<frame>` being `none` when
    /// the item has no key or the bar has not laid it out.
    static let overlayActionBar = SocketCommand("overlay-actionbar")
    /// `overlay-press <item id>`: runs an Action bar item's action, as its button does. Replies
    /// `ok`; an error when no Action bar is showing.
    static let overlayPress = SocketCommand("overlay-press")
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
        register(.overlayPress) { request in
            guard let controller = AreaCaptureFlow.activeOverlay else { return "error no overlay" }
            guard controller.actionBarFrame != nil else { return "error no Action bar" }
            guard let id = request.arguments.first, let item = ActionBarRegistry.item(id: id) else {
                return "error overlay-press <item id>"
            }
            item.perform(on: controller)
            return "ok"
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
        guard let container = containers.first(where: { $0.actionBarFrame != nil }), let bar = container.actionBarFrame
        else { return ["frame=none"] }
        var lines = ["frame=\(describe(bar))"]
        for item in ActionBarRegistry.all {
            let frame = container.itemFrames[item.id].map { describe($0.offsetBy(dx: bar.minX, dy: bar.minY)) }
            lines.append("item \(item.id)|\(item.title)|\(item.tooltip)|\(item.keyEquivalent ?? "none")|\(frame ?? "none")")
        }
        return lines
    }
}
