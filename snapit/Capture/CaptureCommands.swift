import Foundation

nonisolated extension SocketCommand {
    /// `fixture-display <scale> [<point width> <point height>]`: chooses the fake display the
    /// fixture Capture source returns. Replies `ok <pixel width>x<pixel height> <color space>`.
    static let fixtureDisplay = SocketCommand("fixture-display")
    /// Replies `fixture` when the Capture source is the test one. Test mode only.
    static let captureSource = SocketCommand("capture-source")
    /// `frame-freed-at-open`: `yes` when the frozen frame of the latest Capture was already gone (its
    /// file written) when the Editor was asked to open it, `no` while it was still held, `none`
    /// before any Capture, `unknown` when the frame carried no lifetime probe. Test mode only.
    static let frameFreedAtOpen = SocketCommand("frame-freed-at-open")
}

extension SocketCommandRegistry {
    func registerCaptureTestCommands() {
        guard TestMode.isActive else { return }
        register(.fixtureDisplay) { request in
            let numbers = request.arguments.compactMap(Int.init)
            guard let scale = numbers.first, (1...3).contains(scale) else { return "error scale must be 1, 2 or 3" }
            var display = FixtureCaptureSource.shared.display
            display.scale = scale
            if numbers.count >= 3, numbers[1] > 0, numbers[2] > 0 {
                display.pointWidth = numbers[1]
                display.pointHeight = numbers[2]
            }
            FixtureCaptureSource.shared.display = display
            return "ok \(display.pointWidth * scale)x\(display.pointHeight * scale) \(display.colorSpaceName)"
        }
        register(.captureSource) { _ in
            CaptureSources.current is FixtureCaptureSource ? "fixture" : "screencapturekit"
        }
        register(.frameFreedAtOpen) { _ in
            if CaptureHandoff.frameProbeMissing { return "unknown" }
            switch CaptureHandoff.frameFreedAtOpen {
            case true?: return "yes"
            case false?: return "no"
            case nil: return "none"
            }
        }
    }
}
