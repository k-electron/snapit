/// How the Area overlay ended. `AreaCaptureFlow.finish` turns each outcome into what happens next;
/// a new way out of the overlay (Timed Capture) adds one case here and one arm there.
enum AreaOverlayOutcome: Equatable {
    /// Capture this Area now.
    case capture(AreaSelection)
    /// Esc, the Cancel button, or the displays changed: nothing is captured.
    case cancel
}
