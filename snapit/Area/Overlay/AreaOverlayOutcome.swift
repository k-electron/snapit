/// How the Area overlay ended. `AreaCaptureFlow.finish` turns each outcome into what happens next;
/// a new way out of the overlay (Timed Capture) adds one case here and one arm there.
enum AreaOverlayOutcome: Equatable {
    /// Capture this Area now.
    case capture(AreaSelection)
    /// Capture this Area after a countdown of this many seconds (Timed Capture).
    case timed(AreaSelection, seconds: Int)
    /// Esc, the Cancel button, or the displays changed: nothing is captured.
    case cancel
}
