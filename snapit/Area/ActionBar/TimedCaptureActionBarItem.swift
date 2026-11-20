import CoreGraphics

/// Capture in N s: starts a Timed Capture of the selected Area with the timer slider's seconds.
/// The overlay goes, the desktop is the user's again, and a countdown runs (`TimedCountdown`).
struct TimedCaptureActionBarItem: ActionBarItem {
    let id = "timed-capture"
    let order = 210
    var title: String { Self.title(TimedCaptureSettings.seconds) }
    let tooltip = "Capture this Area after the countdown"

    static func title(_ seconds: Int) -> String { "Capture in \(seconds) s" }

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
