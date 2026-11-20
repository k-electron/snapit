import AppKit

/// Test mode's frozen frames: the fixture image of `FixtureCaptureSource`, once for the fake
/// display `fixture-display` chose, and once more for a second display when
/// `fixture-extra-display` adds one (placed to the right of the first, with its own scale and
/// size, so a mixed-scale desk can be tested).
///
/// The displays' frames are placed on the real desktop, a little in from the main screen's
/// bottom-left corner, so the overlay's panels cover only the fixture's size and the scripted
/// run never blocks the user's whole screen.
@MainActor
final class FixtureAreaCaptureSource: AreaCaptureSource {
    static let shared = FixtureAreaCaptureSource()

    /// A second fake display to the right of the first; nil for none.
    var extraDisplay: FixtureCaptureSource.Display?

    var displays: [FixtureCaptureSource.Display] {
        [FixtureCaptureSource.shared.display] + (extraDisplay.map { [$0] } ?? [])
    }

    /// The pointer starts in the middle of the first display.
    var pointerLocation: CGPoint {
        let first = frames()[0]
        return CGPoint(x: first.midX, y: first.midY)
    }

    func freezeDisplays() async throws -> [FrozenDisplay] {
        var frozen: [FrozenDisplay] = []
        let frames = frames()
        var left = 0.0
        for (display, frame) in zip(displays, frames) {
            let image = try FixtureCaptureSource.makeImage(display)
            frozen.append(
                FrozenDisplay(
                    frame: frame, cgOrigin: CGPoint(x: left, y: 0),
                    screen: CapturedScreen(image: image, scale: Double(display.scale))))
            left += Double(display.pointWidth)
        }
        return frozen
    }

    /// The displays' frames in AppKit's global space, side by side.
    private func frames() -> [CGRect] {
        let anchor = NSScreen.screens.first?.visibleFrame.origin ?? .zero
        var x = anchor.x + 40
        return displays.map { display in
            defer { x += Double(display.pointWidth) }
            return CGRect(
                x: x, y: anchor.y + 40, width: Double(display.pointWidth), height: Double(display.pointHeight))
        }
    }
}
