import AppKit
import Foundation

nonisolated extension SocketCommand {
    /// What a Timed Capture shows now, as `key=value` lines: `state` (`counting` or `none`), `seconds`,
    /// `remaining`, `ticking` (a tick is scheduled), `area`, `border` and `badge` (display points from the
    /// display's top-left corner), `border-panels`, `border-click-through` (every border panel lets
    /// clicks through), `tooltip` (the ✕'s tooltip once the pointer has rested on it, or `none`). Then
    /// the fresh Capture at zero: `fresh-captures` (how many so far), `fresh-after` (seconds from the
    /// countdown's start, or `none`) and `fresh-excluded` (how many windows of snapit's the content filter
    /// excluded). Test mode only.
    static let timedFacts = SocketCommand("timed-facts")
    /// `timed-mouse move|down|up cross|body|away`: sends the countdown badge a real mouse `NSEvent`
    /// over its ✕, over its seconds, or away from it. Replies `ok`. Test mode only.
    static let timedMouse = SocketCommand("timed-mouse")
    /// `fixture-fresh-ignores-exclusions on|off`: the fixture's fresh Capture paints snapit's windows
    /// whatever the content filter excludes, to show a Capture that let them through. Test mode only.
    /// `timed-seconds-store <integer>|<text>`: stores that raw value (an integer, as the slider
    /// does, however far out of range; or text that is not a number) under the timer's key, to see
    /// how the Action bar reads it. Replies `ok`. Test mode only.
    static let timedSecondsStore = SocketCommand("timed-seconds-store")
    static let fixtureFreshIgnoresExclusions = SocketCommand("fixture-fresh-ignores-exclusions")
}

extension SocketCommandRegistry {
    /// The Timed Capture's test-mode commands. They exist only while test mode is on; the Area
    /// overlay's registration calls this.
    func registerTimedCaptureTestCommands() {
        guard TestMode.isActive else { return }

        register(.timedFacts) { _ in AreaCaptureFlow.timedFacts().joined(separator: "\n") }
        register(.timedMouse) { request in
            guard let timed = AreaCaptureFlow.countdown, let badge = timed.badge,
                let view = (badge.contentView as? NSGlassEffectView)?.contentView as? TimedBadgeView
            else { return "error no countdown" }
            let arguments = request.arguments
            guard arguments.count == 2, ["move", "down", "up"].contains(arguments[0]) else {
                return "error timed-mouse move|down|up cross|body|away"
            }
            let size = TimedBadgePlacement.size
            let points = [
                "cross": CGPoint(x: size.width - TimedBadgeView.crossWidth / 2, y: size.height / 2),
                "body": CGPoint(x: 20, y: size.height / 2), "away": CGPoint(x: -40, y: size.height / 2),
            ]
            guard let point = points[arguments[1]] else { return "error timed-mouse move|down|up cross|body|away" }
            let types: [String: NSEvent.EventType] = ["move": .mouseMoved, "down": .leftMouseDown, "up": .leftMouseUp]
            let type = types[arguments[0]]!
            guard
                let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: badge.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                    pressure: type == .leftMouseUp ? 0 : 1)
            else { return "error no mouse event" }
            if type == .mouseMoved { view.mouseMoved(with: event) } else { badge.sendEvent(event) }
            return "ok"
        }
        register(.timedSecondsStore) { request in
            guard let value = request.arguments.first else { return "error timed-seconds-store <integer>|<text>" }
            if let number = Int(value) {
                AppDefaults.store.set(number, forKey: TimedCaptureSettings.secondsKey)
            } else {
                AppDefaults.store.set(value, forKey: TimedCaptureSettings.secondsKey)
            }
            return "ok"
        }
        register(.fixtureFreshIgnoresExclusions) { request in
            guard let mode = request.arguments.first, mode == "on" || mode == "off" else {
                return "error fixture-fresh-ignores-exclusions on|off"
            }
            FixtureTimedCaptureSource.shared.ignoresExclusions = mode == "on"
            return "ok"
        }
    }
}

extension AreaCaptureFlow {
    static func timedFacts() -> [String] {
        func describe(_ rect: CGRect) -> String {
            func number(_ value: Double) -> String {
                var text = String(format: "%.2f", value)
                while text.contains("."), text.hasSuffix("0") || text.hasSuffix(".") { text.removeLast() }
                return text
            }
            return "\(number(rect.minX)),\(number(rect.minY)) \(number(rect.width))x\(number(rect.height))"
        }
        var lines: [String] = []
        if let timed = countdown {
            lines += [
                "state=counting", "seconds=\(timed.seconds)", "remaining=\(timed.remaining)",
                "ticking=\(timed.isTicking ? "yes" : "no")", "area=\(describe(timed.area))",
                "border=\(describe(timed.borderRect))", "badge=\(describe(timed.badgeRect))",
                "border-panels=\(timed.strips.count)",
                "border-click-through=\(timed.strips.allSatisfy(\.isClickThrough) ? "yes" : "no")",
                "badge-click-through=\(timed.badge?.isClickThrough == false ? "no" : "yes")",
                "tooltip=\(timed.tooltipText ?? "none")",
            ]
        } else {
            lines += ["state=none", "ticking=no"]
        }
        let fixture = FixtureTimedCaptureSource.shared
        lines.append("fresh-captures=\(fixture.captureCount)")
        if let at = fixture.lastCapture, let started = lastStartedAt {
            let elapsed = at - started
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            lines.append("fresh-after=\(String(format: "%.2f", seconds))")
        } else {
            lines.append("fresh-after=none")
        }
        lines.append("fresh-excluded=\(fixture.lastExcluded.count)")
        return lines
    }
}
