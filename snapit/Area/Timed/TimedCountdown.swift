import AppKit
import QuartzCore

/// What a Timed Capture shows while it counts down, and nothing else: a click-through border just
/// outside the Area, a small badge with the seconds left and a ✕, and the tick that moves it.
///
/// The border is four thin panels (a ring of panels of the Area's size would be a window as big as
/// the Area), the badge a panel the size of a pill. All are persistent Core Animation layers in
/// panels owned by the menu bar app, above everything and on every Space, so the desktop stays the
/// user's. The tick is a dispatch timer that is set for one second at a time and exists only
/// between `start()` and `close()`; at rest nothing is scheduled.
@MainActor
final class TimedCountdown {
    /// What the countdown is about: the Area, fixed when the overlay went away.
    struct Target {
        let displayID: CGDirectDisplayID
        /// The display's frame in AppKit's global space.
        let frame: CGRect
        let scale: Double
        let pixels: PixelRect
    }

    static let borderWidth: CGFloat = 2
    static let tooltipDelay: TimeInterval = 0.5
    static let crossTooltip = "Cancel the countdown"

    let target: Target
    let seconds: Int
    private(set) var remaining: Int
    /// When the countdown started, for the scripted run.
    private(set) var startedAt: ContinuousClock.Instant?
    var onCancel: (() -> Void)?
    /// The seconds ran out. The tick is already gone; the windows stay until `close()`.
    var onZero: (() -> Void)?

    /// The Area in display points (top-left origin), where its device pixels are.
    let area: CGRect
    private(set) var strips: [TimedPanel] = []
    private(set) var badge: TimedPanel?
    private var badgeView: TimedBadgeView?
    private let tooltip = TimedTooltip()
    private var tooltipTimer: DispatchWorkItem?
    private var timer: DispatchSourceTimer?
    private var timerBase = DispatchTime.now()
    private var screenObserver: NSObjectProtocol?

    init(target: Target, seconds: Int) {
        self.target = target
        self.seconds = seconds
        remaining = seconds
        area = AreaGeometry.points(of: target.pixels, scale: target.scale)
    }

    /// True while a tick is scheduled.
    var isTicking: Bool { timer != nil }

    /// The border's rectangle: the Area grown by the border's width, display points.
    var borderRect: CGRect { area.insetBy(dx: -Self.borderWidth, dy: -Self.borderWidth) }

    /// The badge's frame in display points (top-left origin).
    var badgeRect: CGRect {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == target.displayID
        }
        let topInset = screen.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 0
        return TimedBadgePlacement.frame(
            border: borderRect, in: CGRect(origin: .zero, size: target.frame.size), topInset: topInset)
    }

    /// The panels on screen now, for the Capture's content filter and for the scripted run.
    var ownWindows: [OwnWindow] {
        var windows = strips.map { OwnWindow(number: $0.windowNumber, frame: $0.frame, kind: .border) }
        if let badge { windows.append(OwnWindow(number: badge.windowNumber, frame: badge.frame, kind: .badge)) }
        if let panel = tooltip.panel {
            windows.append(OwnWindow(number: panel.windowNumber, frame: panel.frame, kind: .tooltip))
        }
        return windows
    }

    var tooltipText: String? { tooltip.text }

    /// Display points (top-left origin) to AppKit's global space.
    private func global(_ rect: CGRect) -> CGRect {
        CGRect(x: target.frame.minX + rect.minX, y: target.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Showing

    func start() {
        let width = Self.borderWidth
        let outer = borderRect
        let color = NSColor.controlAccentColor.cgColor
        // Top, bottom, left and right, outside the Area.
        let rects = [
            CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: width),
            CGRect(x: outer.minX, y: outer.maxY - width, width: outer.width, height: width),
            CGRect(x: outer.minX, y: outer.minY + width, width: width, height: outer.height - 2 * width),
            CGRect(x: outer.maxX - width, y: outer.minY + width, width: width, height: outer.height - 2 * width),
        ]
        for rect in rects {
            let strip = TimedPanel(frame: global(rect), takesClicks: false)
            let layer = CALayer()
            layer.backgroundColor = color
            strip.host(layer)
            strip.orderFrontRegardless()
            strips.append(strip)
        }

        let badge = TimedPanel(frame: global(badgeRect), takesClicks: true)
        let view = TimedBadgeView(scale: CGFloat(target.scale), seconds: remaining)
        view.onCancel = { [weak self] in self?.onCancel?() }
        view.onCrossHover = { [weak self] over in self?.crossHover(over) }
        badge.contentView = view
        badge.setFrame(global(badgeRect), display: false)
        badge.orderFrontRegardless()
        self.badge = badge
        badgeView = view

        // A display plugged in, unplugged or rearranged ends the countdown, as it ends the overlay.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onCancel?() }
        }

        startedAt = .now
        timerBase = .now()
        scheduleTick(after: 1)
        CATransaction.flush()
    }

    // MARK: The tick

    /// One second after the countdown started, two seconds after it, and so on: each tick is set
    /// for its own moment, so the tick's own delay never adds up.
    private func scheduleTick(after seconds: Int) {
        guard let timer = self.timer else {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            self.timer = timer
            timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.tick() } }
            timer.schedule(deadline: timerBase + .seconds(seconds), leeway: .milliseconds(5))
            timer.resume()
            return
        }
        timer.schedule(deadline: timerBase + .seconds(seconds), leeway: .milliseconds(5))
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 {
            remaining = 0
            stopTicking()
            badgeView?.show(seconds: 0)
            onZero?()
        } else {
            badgeView?.show(seconds: remaining)
            scheduleTick(after: seconds - remaining + 1)
        }
    }

    /// Cancels the tick. Its handler is dropped first: a source must not be released while
    /// suspended or with a handler still set.
    func stopTicking() {
        guard let timer else { return }
        timer.setEventHandler {}
        timer.cancel()
        self.timer = nil
    }

    // MARK: The ✕'s tooltip

    private func crossHover(_ over: Bool) {
        tooltipTimer?.cancel()
        tooltipTimer = nil
        tooltip.close()
        guard over else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.badge != nil else { return }
            self.tooltip.show(
                Self.crossTooltip, near: self.badgeRect, in: self.target.frame, scale: CGFloat(self.target.scale))
        }
        tooltipTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tooltipDelay, execute: work)
    }

    // MARK: Taking the windows away

    /// Takes the border, the badge and the tooltip off screen (they stay until `close()`).
    func hideWindows() {
        for panel in strips { panel.orderOut(nil) }
        badge?.orderOut(nil)
        tooltip.panel?.orderOut(nil)
    }

    /// Ends the countdown: no tick, no windows, no observers.
    func close() {
        stopTicking()
        tooltipTimer?.cancel()
        tooltipTimer = nil
        tooltip.close()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        onCancel = nil
        onZero = nil
        badgeView?.onCancel = nil
        badgeView?.onCrossHover = nil
        for panel in strips + (badge.map { [$0] } ?? []) {
            panel.contentView = nil
            panel.orderOut(nil)
            panel.close()
        }
        strips.removeAll()
        badge = nil
        badgeView = nil
        // Core Animation holds on to what it last committed until the next commit.
        CATransaction.flush()
    }
}
