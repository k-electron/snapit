import CoreGraphics
import Foundation

/// Test mode's fresh Capture at zero. It returns the fixture image of the fake display, changed
/// the way a screen changes between the Area being chosen and the countdown ending, so a run can
/// tell it was taken at zero and not from the frozen frame:
///
/// - a 4 x 4 pixel stamp at the display's top-left corner, `R = 250, G = <how many fresh Captures
///   so far, from 1>, B = 77` (the fixture formula's pixels there are different, and the frozen
///   frame has no stamp);
/// - every window of snapit's that is on screen and not excluded by `OwnWindowExclusion` (the
///   decision the real content filter is built from), painted over the frame (the border in pink,
///   the badge nearly black), as a real screen would show it.
///
/// `fixture-fresh-ignores-exclusions on` paints them all whatever is excluded, so a run can see
/// that a Capture that lets them through would show them.
@MainActor
final class FixtureTimedCaptureSource: TimedCaptureSource {
    static let shared = FixtureTimedCaptureSource()

    /// The stamp's side in device pixels, and its color.
    static let stampSide = 4
    static let stampRed: UInt8 = 250
    static let stampBlue: UInt8 = 77

    /// How many fresh Captures were taken, when the last one was, and what it excluded.
    private(set) var captureCount = 0
    private(set) var lastCapture: ContinuousClock.Instant?
    private(set) var lastExcluded: [Int] = []
    /// When true, snapit's windows are painted whatever the request excludes.
    var ignoresExclusions = false

    func captureFresh(_ request: FreshCaptureRequest, hideOwnWindows: @MainActor () -> Void) async throws
        -> CapturedScreen
    {
        if FixtureCaptureSource.shared.fails { throw ScreenCaptureError.noImage }
        let index = Int(request.displayID) - Int(FixtureAreaCaptureSource.firstDisplayID)
        let displays = FixtureAreaCaptureSource.shared.displays
        guard displays.indices.contains(index) else { throw ScreenCaptureError.noDisplay }
        let display = displays[index]
        captureCount += 1
        lastCapture = .now
        // snapit is always "listed" in the fixture's content; the same decision the real filter
        // is built from says which of its windows are kept out.
        let exclusion = OwnWindowExclusion.plan(
            applicationListed: true, ownWindows: request.ownWindows.map { .init(number: $0.number, layer: $0.layer) })
        let excluded = request.ownWindows.filter { exclusion.excludes(.init(number: $0.number, layer: $0.layer)) }
        lastExcluded = excluded.map(\.number).sorted()

        let base = try FixtureCaptureSource.makeImage(display)
        let width = base.width, height = base.height
        let scale = CGFloat(display.scale)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: display.colorSpace, bitmapInfo: bitmapInfo)
        else { throw ScreenCaptureError.noImage }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setBlendMode(.normal)

        func paint(_ rect: CGRect, _ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            let components = [red, green, blue].map { CGFloat($0) / 255 } + [1]
            context.setFillColor(CGColor(colorSpace: display.colorSpace, components: components)!)
            context.fill(rect)
        }
        let ownWindows = ignoresExclusions ? request.ownWindows : request.ownWindows.filter { !excluded.contains($0) }
        for window in ownWindows {
            // The frame in device pixels, from the display's bottom-left corner like the context.
            let rect = CGRect(
                x: (window.frame.minX - request.displayFrame.minX) * scale,
                y: (window.frame.minY - request.displayFrame.minY) * scale,
                width: window.frame.width * scale, height: window.frame.height * scale)
            switch window.kind {
            case .border: paint(rect, 255, 46, 160)
            case .badge: paint(rect, 20, 20, 20)
            case .tooltip: paint(rect, 0, 0, 0)
            }
        }
        let side = CGFloat(Self.stampSide)
        paint(
            CGRect(x: 0, y: CGFloat(height) - side, width: side, height: side), Self.stampRed,
            UInt8(truncatingIfNeeded: captureCount), Self.stampBlue)
        guard let image = context.makeImage() else { throw ScreenCaptureError.noImage }
        return CapturedScreen(image: image, scale: Double(display.scale))
    }
}
