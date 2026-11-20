import AppKit
import Foundation

nonisolated extension SocketCommand {
    /// What the Color picker shows now, as `key=value` lines (`display`, `pixel` as `<x>,<y>` in the
    /// display's device pixels, `hex`, `origin` `bar` or `entry`, `frame` the display's size in
    /// pixels, `loupe` the loupe's frame in display points, `outlined` the centre of the outlined
    /// cell and `swatch` the centre of the swatch, in display points). `none` when the picker is not up.
    static let overlayPicker = SocketCommand("overlay-picker")
    /// The text of the "Copied #…" toast showing now, or `none`.
    static let colorToast = SocketCommand("color-toast")
    /// The plain text on the private pasteboard, or `none`.
    static let pasteboardString = SocketCommand("pasteboard-string")
}

extension SocketCommandRegistry {
    /// The Color picker's test-mode commands. They exist only while test mode is on; the Area
    /// overlay's registration calls this.
    func registerPickColorTestCommands() {
        guard TestMode.isActive else { return }

        register(.overlayPicker) { _ in
            guard let controller = AreaCaptureFlow.activeOverlay, let lines = controller.pickerFacts() else {
                return "none"
            }
            return lines.joined(separator: "\n")
        }
        register(.colorToast) { _ in ColorToast.text ?? "none" }
        register(.pasteboardString) { _ in AppPasteboard.current.string(forType: .string) ?? "none" }
    }
}

extension AreaOverlayController {
    func pickerFacts() -> [String]? {
        guard state == .pickingColor, let picker else { return nil }
        let image = displays[picker.displayIndex].image
        func number(_ value: Double) -> String {
            var text = String(format: "%.2f", value)
            while text.contains("."), text.hasSuffix("0") || text.hasSuffix(".") { text.removeLast() }
            return text
        }
        var lines = [
            "display=\(picker.displayIndex)",
            "pixel=\(picker.pixel.x),\(picker.pixel.y)",
            "hex=\(PixelSampler.color(in: image, at: picker.pixel)?.hex ?? "none")",
            "origin=\(picker.origin == .actionBar ? "bar" : "entry")",
            "frame=\(image.width)x\(image.height)",
        ]
        if let frame = views[picker.displayIndex].scene.pickLoupeFrame {
            lines.append("loupe=\(number(frame.minX)),\(number(frame.minY)) \(number(frame.width))x\(number(frame.height))")
            lines.append(
                "outlined=\(number(frame.minX + PickLoupe.outlinedCentre.x)),\(number(frame.minY + PickLoupe.outlinedCentre.y))")
            lines.append(
                "swatch=\(number(frame.minX + PickLoupe.swatchCentre.x)),\(number(frame.minY + PickLoupe.swatchCentre.y))")
        } else {
            lines.append("loupe=none")
        }
        return lines
    }
}
