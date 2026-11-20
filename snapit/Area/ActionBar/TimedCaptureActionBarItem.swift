import CoreGraphics

/// Capture in N s: starts a Timed Capture of the selected Area with the timer slider's seconds.
/// The overlay goes, the desktop is the user's again, and a countdown runs (`TimedCountdown`).
struct TimedCaptureActionBarItem: ActionBarItem {
    let id = "timed-capture"
    let order = 210
    var title: String { Self.title(TimedCaptureSettings.seconds) }
    let tooltip = "Capture this Area after the countdown"

    static func title(_ seconds: Int) -> String { "Capture in \(seconds) s" }

    /// A stopwatch: a dial, its button and one hand.
    var glyph: CGPath? {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: 1.5, y: 0.8, width: 11, height: 11))
        path.move(to: CGPoint(x: 5.5, y: 13.2))
        path.addLine(to: CGPoint(x: 8.5, y: 13.2))
        path.move(to: CGPoint(x: 7, y: 6.3))
        path.addLine(to: CGPoint(x: 9.2, y: 8.6))
        return path
    }

    func perform(on host: any ActionBarHost) {
        guard let area = host.selectedArea else { return }
        host.finish(with: .timed(area, seconds: TimedCaptureSettings.seconds))
    }

    func makeControl(context: ActionBarContext) -> ActionBarControl {
        // Sized for the longest title, so the slider never changes the bar's width.
        let control = ActionBarButtonControl(item: self, context: context, widestTitle: Self.title(10))
        TimerValue.observe(control) { [weak control] seconds in control?.setTitle(Self.title(seconds)) }
        return control
    }
}
