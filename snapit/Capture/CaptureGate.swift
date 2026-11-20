/// One Capture at a time, whichever Capture mode starts it: a Shortcut pressed while another
/// Capture is still running does nothing. Every Capture flow takes the gate with `enter()` and
/// gives it back with `leave()`.
@MainActor
enum CaptureGate {
    private static var isBusy = false

    /// True when the caller now holds the gate; false when another Capture is running.
    static func enter() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    static func leave() {
        isBusy = false
    }
}
