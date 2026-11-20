import AppKit

/// Test mode's frozen frames: the fixture image of `FixtureCaptureSource`, once for the fake
/// display `fixture-display` chose, and once more for a second display when
/// `fixture-extra-display` adds one (to the right of the first, or to its left or above it, with
/// its own scale and size, so a mixed-scale desk and displays at negative coordinates can be
/// tested).
///
/// The displays' frames are placed on the real desktop, a little in from the main screen's
/// bottom-left corner, so the overlay's panels cover only the fixture's size and the scripted
/// run never blocks the user's whole screen. The first display is the primary one: its top-left
/// corner is the origin of the window list's space, and every display's `cgOrigin` is worked
/// out from its AppKit frame the way it is for real displays.
@MainActor
final class FixtureAreaCaptureSource: AreaCaptureSource {
    static let shared = FixtureAreaCaptureSource()

    enum Placement: String {
        case right, left, above
    }

    /// A second fake display; nil for none.
    var extraDisplay: FixtureCaptureSource.Display?
    var extraPlacement = Placement.right

    var displays: [FixtureCaptureSource.Display] {
        [FixtureCaptureSource.shared.display] + (extraDisplay.map { [$0] } ?? [])
    }

    /// The pointer starts in the middle of the first display.
    var pointerLocation: CGPoint {
        let first = frames()[0]
        return CGPoint(x: first.midX, y: first.midY)
    }

    func freezeDisplays() async throws -> [FrozenDisplay] {
        if FixtureCaptureSource.shared.delay > .zero { try await Task.sleep(for: FixtureCaptureSource.shared.delay) }
        if FixtureCaptureSource.shared.fails { throw ScreenCaptureError.noImage }
        let frames = frames()
        let primary = frames[0]
        var frozen: [FrozenDisplay] = []
        for (display, frame) in zip(displays, frames) {
            let image = try FixtureCaptureSource.makeImage(display)
            // AppKit's global space has its origin at the bottom left of the primary display, the
            // window list's at its top left.
            let cgOrigin = CGPoint(x: frame.minX - primary.minX, y: primary.maxY - frame.maxY)
            frozen.append(
                FrozenDisplay(
                    frame: frame, cgOrigin: cgOrigin,
                    screen: CapturedScreen(image: image, scale: Double(display.scale))))
        }
        return frozen
    }

    /// The displays' frames in AppKit's global space.
    private func frames() -> [CGRect] {
        let sizes = displays.map { CGSize(width: Double($0.pointWidth), height: Double($0.pointHeight)) }
        // Top-left corners in the primary display's top-left-origin space.
        var corners = [CGPoint.zero]
        if sizes.count > 1 {
            switch extraPlacement {
            case .right: corners.append(CGPoint(x: sizes[0].width, y: 0))
            case .left: corners.append(CGPoint(x: -sizes[1].width, y: 0))
            case .above: corners.append(CGPoint(x: 0, y: -sizes[1].height))
            }
        }
        let minX = corners.map(\.x).min() ?? 0
        let minY = corners.map(\.y).min() ?? 0
        let deskHeight = zip(corners, sizes).map { $0.y + $1.height }.max()! - minY
        let anchor = NSScreen.screens.first?.visibleFrame.origin ?? .zero
        return zip(corners, sizes).map { corner, size in
            CGRect(
                x: anchor.x + 40 + corner.x - minX, y: anchor.y + 40 + deskHeight - (corner.y - minY) - size.height,
                width: size.width, height: size.height)
        }
    }
}
