import AppKit
import QuartzCore

/// The Timed Capture's timer: a slider of whole seconds, 1 to 10, whose value is remembered
/// across launches (`TimedCaptureSettings`). "Capture in N s" beside it shows the value.
struct TimerSliderActionBarItem: ActionBarItem {
    let id = "timer"
    let order = 200
    var title: String { "Timer \(TimedCaptureSettings.seconds) s" }
    let tooltip = "Timer: 1 to 10 s for a Timed Capture"

    func perform(on host: any ActionBarHost) {}

    func makeControl(context: ActionBarContext) -> ActionBarControl {
        TimerSliderControl(item: self)
    }
}

/// Tells the tiles that show the timer's value when the slider moves. Controls are released with
/// the Action bar, so listeners are held weakly.
@MainActor
enum TimerValue {
    private final class Listener {
        weak var owner: AnyObject?
        let changed: (Int) -> Void
        init(owner: AnyObject, changed: @escaping (Int) -> Void) {
            self.owner = owner
            self.changed = changed
        }
    }
    private static var listeners: [Listener] = []

    static func observe(_ owner: AnyObject, _ changed: @escaping (Int) -> Void) {
        listeners.removeAll { $0.owner == nil }
        listeners.append(Listener(owner: owner, changed: changed))
    }

    /// The slider chose `seconds`: it is remembered and shown.
    static func set(_ seconds: Int) {
        guard seconds != TimedCaptureSettings.seconds else { return }
        TimedCaptureSettings.seconds = seconds
        listeners.removeAll { $0.owner == nil }
        for listener in listeners { listener.changed(seconds) }
    }
}

/// A track, its filled part and a knob, as three layers. The whole tile is the hit area: a press
/// anywhere on it sets the value from the pointer's x, and a drag follows the pointer even past the
/// tile's ends.
final class TimerSliderControl: ActionBarControl {
    static let width: CGFloat = 112
    private static let inset: CGFloat = 16
    private static let knobSize: CGFloat = 16

    private let track = CALayer()
    private let fill = CALayer()
    private let knob = CALayer()

    init(item: TimerSliderActionBarItem) {
        super.init(
            id: item.id, tooltip: item.tooltip,
            preferredSize: CGSize(width: Self.width, height: ActionBarButtonControl.height))
        layer.cornerRadius = ActionBarButtonControl.height / 2

        let trackWidth = Self.width - 2 * Self.inset
        let middle = ActionBarButtonControl.height / 2
        track.frame = CGRect(x: Self.inset, y: middle - 2, width: trackWidth, height: 4)
        track.cornerRadius = 2
        track.backgroundColor = CGColor(gray: 1, alpha: 0.3)
        layer.addSublayer(track)
        fill.cornerRadius = 2
        fill.backgroundColor = NSColor.controlAccentColor.cgColor
        layer.addSublayer(fill)
        knob.bounds = CGRect(x: 0, y: 0, width: Self.knobSize, height: Self.knobSize)
        knob.cornerRadius = Self.knobSize / 2
        knob.backgroundColor = CGColor(gray: 1, alpha: 1)
        knob.borderColor = CGColor(gray: 0, alpha: 0.35)
        knob.borderWidth = 0.5
        layer.addSublayer(knob)
        show(TimedCaptureSettings.seconds)
        stateChanged()
    }

    /// The x of the knob's centre for `seconds`, in the tile.
    static func x(for seconds: Int) -> CGFloat {
        let steps = CGFloat(TimedCaptureSettings.range.count - 1)
        return inset + CGFloat(seconds - TimedCaptureSettings.range.lowerBound) / steps * (width - 2 * inset)
    }

    /// The whole seconds the pointer at `x` chooses.
    static func seconds(at x: CGFloat) -> Int {
        let steps = CGFloat(TimedCaptureSettings.range.count - 1)
        let step = ((x - inset) / (width - 2 * inset) * steps).rounded()
        let seconds = TimedCaptureSettings.range.lowerBound + Int(max(0, min(steps, step)))
        return seconds
    }

    private func show(_ seconds: Int) {
        let x = Self.x(for: seconds)
        knob.position = CGPoint(x: x, y: ActionBarButtonControl.height / 2)
        fill.frame = CGRect(x: Self.inset, y: track.frame.minY, width: x - Self.inset, height: 4)
    }

    private func choose(at point: CGPoint) {
        let seconds = Self.seconds(at: point.x)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        show(seconds)
        CATransaction.commit()
        TimerValue.set(seconds)
    }

    override func stateChanged() {
        layer.backgroundColor = CGColor(gray: 1, alpha: isPressed ? 0.26 : isHovered ? 0.16 : 0)
    }

    override func pointerDown(at point: CGPoint) { choose(at: point) }
    override func pointerDragged(at point: CGPoint) { choose(at: point) }
}
